# Escalation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow quest rosters to chain evaluation steps across local Ollama members and cloud Claude tiers, routing to the next step based on configurable per-step escalation conditions.

**Architecture:** A new `QuestRunner` module replaces direct `Evaluator.evaluate/2` calls for quest execution. It reads the quest's roster steps, fetches DB members matching each step's `who` filter, calls models (Ollama for DB members, Anthropic API for `:claude_*` virtual members), aggregates verdicts per the `how` strategy, then checks `escalate_on` to decide whether to continue to the next step. The existing Evaluator is left unchanged (it still handles the old charter-based path).

**Tech Stack:** Phoenix LiveView, Ecto (server DB), `req` (HTTP), Excellence.LLM.Ollama, Anthropic Messages API.

---

## Task 1: ClaudeClient — Anthropic API wrapper

**Files:**
- Create: `lib/ex_calibur/claude_client.ex`
- Create: `test/ex_calibur/claude_client_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_calibur/claude_client_test.exs
defmodule ExCalibur.ClaudeClientTest do
  use ExUnit.Case, async: true

  alias ExCalibur.ClaudeClient

  describe "parse_response/1" do
    test "extracts action, confidence, reason from text" do
      text = """
      ACTION: pass
      CONFIDENCE: 0.85
      REASON: The content looks good.
      """

      assert {:ok, %{action: "pass", confidence: 0.85, reason: "The content looks good."}} =
               ClaudeClient.parse_response(text)
    end

    test "handles uppercase variants" do
      text = "ACTION: FAIL\nCONFIDENCE: 0.9\nREASON: Too risky."

      assert {:ok, %{action: "fail", confidence: 0.9, reason: "Too risky."}} =
               ClaudeClient.parse_response(text)
    end

    test "returns error when format unrecognized" do
      assert {:error, :unparseable} = ClaudeClient.parse_response("just some random text")
    end
  end

  describe "model_for/1" do
    test "maps claude_haiku to correct model id" do
      assert ClaudeClient.model_for(:claude_haiku) == "claude-haiku-4-5-20251001"
    end

    test "maps claude_sonnet to correct model id" do
      assert ClaudeClient.model_for(:claude_sonnet) == "claude-sonnet-4-6"
    end

    test "maps claude_opus to correct model id" do
      assert ClaudeClient.model_for(:claude_opus) == "claude-opus-4-6"
    end
  end
end
```

**Step 2: Run to confirm failure**

```bash
cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur/claude_client_test.exs
```

Expected: error — module not found.

**Step 3: Implement ClaudeClient**

```elixir
# lib/ex_calibur/claude_client.ex
defmodule ExCalibur.ClaudeClient do
  @moduledoc """
  Thin wrapper around the Anthropic Messages API.
  Sends a system prompt + user message, parses ACTION/CONFIDENCE/REASON response format.
  """

  @models %{
    claude_haiku: "claude-haiku-4-5-20251001",
    claude_sonnet: "claude-sonnet-4-6",
    claude_opus: "claude-opus-4-6"
  }

  def model_for(tier) when is_atom(tier), do: Map.fetch!(@models, tier)

  @doc """
  Call Claude with a system prompt and user message.
  Returns {:ok, %{action, confidence, reason}} or {:error, reason}.
  """
  def call(tier, system_prompt, user_message) do
    api_key = Application.get_env(:ex_calibur, :anthropic_api_key) ||
              System.get_env("ANTHROPIC_API_KEY")

    if is_nil(api_key) do
      {:error, :no_api_key}
    else
      do_call(tier, system_prompt, user_message, api_key)
    end
  end

  defp do_call(tier, system_prompt, user_message, api_key) do
    body = %{
      model: model_for(tier),
      max_tokens: 512,
      system: system_prompt,
      messages: [%{role: "user", content: user_message}]
    }

    case Req.post("https://api.anthropic.com/v1/messages",
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"}
           ]
         ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        parse_response(text)

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @doc """
  Parse ACTION/CONFIDENCE/REASON format from a model response string.
  """
  def parse_response(text) do
    with {:ok, action} <- extract(text, ~r/ACTION:\s*(\S+)/i),
         {:ok, confidence_str} <- extract(text, ~r/CONFIDENCE:\s*([\d.]+)/i),
         {:ok, reason} <- extract(text, ~r/REASON:\s*(.+)/is) do
      case Float.parse(confidence_str) do
        {confidence, _} ->
          {:ok,
           %{
             action: String.downcase(action),
             confidence: confidence,
             reason: String.trim(reason)
           }}

        :error ->
          {:error, :unparseable}
      end
    else
      _ -> {:error, :unparseable}
    end
  end

  defp extract(text, regex) do
    case Regex.run(regex, text, capture: :all_but_first) do
      [match | _] -> {:ok, match}
      _ -> {:error, :not_found}
    end
  end
end
```

**Step 4: Run tests**

```bash
mix test test/ex_calibur/claude_client_test.exs
```

Expected: all passing.

**Step 5: Commit**

```bash
git add lib/ex_calibur/claude_client.ex test/ex_calibur/claude_client_test.exs
git commit -m "feat: add ClaudeClient for Anthropic API"
```

---

## Task 2: QuestRunner — roster-driven multi-step evaluation

**Files:**
- Create: `lib/ex_calibur/quest_runner.ex`
- Create: `test/ex_calibur/quest_runner_test.exs`

**Step 1: Write the failing tests**

```elixir
# test/ex_calibur/quest_runner_test.exs
defmodule ExCalibur.QuestRunnerTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.QuestRunner

  describe "resolve_members/2" do
    test "returns empty list for unknown who" do
      assert [] = QuestRunner.resolve_members("unknown_tier", [])
    end

    test "filters members by rank for apprentice" do
      members = [
        %{config: %{"rank" => "apprentice"}, status: "active"},
        %{config: %{"rank" => "journeyman"}, status: "active"}
      ]

      assert [%{config: %{"rank" => "apprentice"}}] =
               QuestRunner.resolve_members("apprentice", members)
    end

    test "returns all active members for 'all'" do
      members = [
        %{config: %{"rank" => "apprentice"}, status: "active"},
        %{config: %{"rank" => "master"}, status: "active"}
      ]

      assert 2 = length(QuestRunner.resolve_members("all", members))
    end
  end

  describe "should_escalate?/2" do
    test "escalates on matching verdict" do
      step = %{"escalate_on" => %{"type" => "verdict", "values" => ["warn", "fail"]}}
      result = %{verdict: "warn", confidence: 0.9}
      assert QuestRunner.should_escalate?(step, result)
    end

    test "does not escalate when verdict not in list" do
      step = %{"escalate_on" => %{"type" => "verdict", "values" => ["fail"]}}
      result = %{verdict: "pass", confidence: 0.9}
      refute QuestRunner.should_escalate?(step, result)
    end

    test "escalates when confidence below threshold" do
      step = %{"escalate_on" => %{"type" => "confidence", "threshold" => 0.7}}
      result = %{verdict: "pass", confidence: 0.5}
      assert QuestRunner.should_escalate?(step, result)
    end

    test "always escalates for 'always'" do
      step = %{"escalate_on" => "always"}
      result = %{verdict: "pass", confidence: 1.0}
      assert QuestRunner.should_escalate?(step, result)
    end

    test "never escalates for 'never'" do
      step = %{"escalate_on" => "never"}
      result = %{verdict: "fail", confidence: 0.1}
      refute QuestRunner.should_escalate?(step, result)
    end

    test "never escalates when escalate_on is nil" do
      step = %{}
      result = %{verdict: "fail", confidence: 0.1}
      refute QuestRunner.should_escalate?(step, result)
    end
  end

  describe "aggregate_verdicts/2" do
    test "consensus picks majority verdict" do
      verdicts = [
        %{action: "pass", confidence: 0.9},
        %{action: "pass", confidence: 0.8},
        %{action: "fail", confidence: 0.7}
      ]

      assert %{verdict: "pass"} = QuestRunner.aggregate_verdicts(verdicts, "consensus")
    end

    test "unanimous requires all to agree" do
      verdicts = [
        %{action: "pass", confidence: 0.9},
        %{action: "fail", confidence: 0.8}
      ]

      assert %{verdict: "escalate"} = QuestRunner.aggregate_verdicts(verdicts, "unanimous")
    end

    test "solo uses first non-abstain verdict" do
      verdicts = [%{action: "warn", confidence: 0.75}]
      assert %{verdict: "warn"} = QuestRunner.aggregate_verdicts(verdicts, "solo")
    end
  end
end
```

**Step 2: Run to confirm failure**

```bash
mix test test/ex_calibur/quest_runner_test.exs
```

Expected: error — module not found.

**Step 3: Implement QuestRunner**

```elixir
# lib/ex_calibur/quest_runner.ex
defmodule ExCalibur.QuestRunner do
  @moduledoc """
  Executes a quest roster step by step, handling escalation between steps.
  Each step filters DB members by tier, calls their models, aggregates verdicts,
  then checks the escalate_on condition to decide whether to continue.
  Claude virtual members (claude_haiku/sonnet/opus) bypass Ollama and call Anthropic API.
  """

  import Ecto.Query

  alias Excellence.LLM.Ollama
  alias Excellence.Schemas.Member
  alias ExCalibur.ClaudeClient
  alias ExCalibur.Repo

  @claude_tiers ~w(claude_haiku claude_sonnet claude_opus)

  @doc """
  Run a quest against an input string.
  Returns {:ok, %{verdict, confidence, trace}} or {:error, reason}.
  trace is a list of step results showing the escalation path.
  """
  def run(quest, input, opts \\ []) do
    ollama_url = Application.get_env(:ex_calibur, :ollama_url, "http://127.0.0.1:11434")
    ollama = Keyword.get(opts, :ollama, Ollama.new(base_url: ollama_url))

    all_members = Repo.all(from(m in Member, where: m.type == "role" and m.status == "active"))
    on_trigger_steps = Enum.filter(quest.roster, &(&1["when"] == "on_trigger"))
    on_escalation_steps = Enum.filter(quest.roster, &(&1["when"] == "on_escalation"))

    run_steps(on_trigger_steps, on_escalation_steps, input, all_members, ollama, [])
  end

  defp run_steps([], _escalation_steps, _input, _members, _ollama, trace) do
    final = List.last(trace)
    {:ok, %{verdict: final.verdict, confidence: final.confidence, trace: trace}}
  end

  defp run_steps([step | rest_trigger], escalation_steps, input, members, ollama, trace) do
    case run_step(step, input, members, ollama) do
      {:ok, step_result} ->
        new_trace = trace ++ [Map.put(step_result, :step, step)]

        if should_escalate?(step, step_result) && escalation_steps != [] do
          [next_step | rest_escalation] = escalation_steps
          run_steps([next_step | rest_trigger], rest_escalation, input, members, ollama, new_trace)
        else
          run_steps(rest_trigger, escalation_steps, input, members, ollama, new_trace)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_step(step, input, all_members, ollama) do
    who = step["who"]
    how = step["how"] || "consensus"

    if who in @claude_tiers do
      run_claude_step(String.to_existing_atom(who), input)
    else
      members = resolve_members(who, all_members)

      if members == [] do
        {:ok, %{verdict: "abstain", confidence: 0.0, verdicts: []}}
      else
        verdicts = Enum.map(members, &call_member(&1, input, ollama))
        {:ok, aggregate_verdicts(verdicts, how)}
      end
    end
  end

  defp run_claude_step(tier, input) do
    system_prompt = """
    You are an expert evaluator. Review the following content carefully.

    Respond with exactly:
    ACTION: pass | warn | fail | abstain
    CONFIDENCE: 0.0-1.0
    REASON: your reasoning
    """

    case ClaudeClient.call(tier, system_prompt, "Evaluate the following:\n\n#{input}") do
      {:ok, result} ->
        {:ok,
         %{
           verdict: result.action,
           confidence: result.confidence,
           verdicts: [result],
           member: to_string(tier)
         }}

      {:error, reason} ->
        {:error, {:claude_error, tier, reason}}
    end
  end

  defp call_member(member, input, ollama) do
    model = member.config["model"] || "mistral"
    system_prompt = member.config["system_prompt"] || "You are an evaluator."

    prompt = """
    #{system_prompt}

    Evaluate the following content:

    #{input}

    Respond with:
    ACTION: pass | warn | fail | abstain
    CONFIDENCE: 0.0-1.0
    REASON: your reasoning
    """

    case Ollama.complete(ollama, model: model, prompt: prompt) do
      {:ok, text} ->
        case ClaudeClient.parse_response(text) do
          {:ok, parsed} -> parsed
          {:error, _} -> %{action: "abstain", confidence: 0.0, reason: "unparseable response"}
        end

      {:error, _} ->
        %{action: "abstain", confidence: 0.0, reason: "ollama error"}
    end
  end

  @doc """
  Filter the full member list by the step's `who` value.
  """
  def resolve_members("all", members), do: Enum.filter(members, &(&1.status == "active"))

  def resolve_members(tier, members) when tier in ~w(apprentice journeyman master) do
    Enum.filter(members, fn m ->
      m.status == "active" && m.config["rank"] == tier
    end)
  end

  def resolve_members(id, members) do
    Enum.filter(members, &(to_string(&1.id) == id))
  end

  @doc """
  Aggregate a list of member verdict maps into a single step result.
  """
  def aggregate_verdicts(verdicts, "solo") do
    first = Enum.find(verdicts, &(&1.action != "abstain")) || List.first(verdicts)
    %{verdict: first.action, confidence: first.confidence, verdicts: verdicts}
  end

  def aggregate_verdicts(verdicts, "first_to_pass") do
    first_pass = Enum.find(verdicts, &(&1.action == "pass"))
    result = first_pass || List.first(verdicts)
    %{verdict: result.action, confidence: result.confidence, verdicts: verdicts}
  end

  def aggregate_verdicts(verdicts, "unanimous") do
    non_abstain = Enum.reject(verdicts, &(&1.action == "abstain"))
    actions = Enum.map(non_abstain, & &1.action) |> Enum.uniq()

    if length(actions) == 1 do
      avg_confidence = avg_confidence(non_abstain)
      %{verdict: hd(actions), confidence: avg_confidence, verdicts: verdicts}
    else
      %{verdict: "escalate", confidence: 0.0, verdicts: verdicts}
    end
  end

  def aggregate_verdicts(verdicts, _consensus) do
    non_abstain = Enum.reject(verdicts, &(&1.action == "abstain"))

    if non_abstain == [] do
      %{verdict: "abstain", confidence: 0.0, verdicts: verdicts}
    else
      majority =
        non_abstain
        |> Enum.group_by(& &1.action)
        |> Enum.max_by(fn {_action, vs} -> length(vs) end)
        |> elem(0)

      matching = Enum.filter(non_abstain, &(&1.action == majority))
      %{verdict: majority, confidence: avg_confidence(matching), verdicts: verdicts}
    end
  end

  defp avg_confidence([]), do: 0.0

  defp avg_confidence(verdicts) do
    total = Enum.reduce(verdicts, 0.0, &(&1.confidence + &2))
    total / length(verdicts)
  end

  @doc """
  Determine whether a step result meets the escalation condition.
  """
  def should_escalate?(%{"escalate_on" => "always"}, _result), do: true
  def should_escalate?(%{"escalate_on" => "never"}, _result), do: false
  def should_escalate?(%{}, _result), do: false

  def should_escalate?(%{"escalate_on" => %{"type" => "verdict", "values" => values}}, result) do
    result.verdict in values
  end

  def should_escalate?(
        %{"escalate_on" => %{"type" => "confidence", "threshold" => threshold}},
        result
      ) do
    result.confidence < threshold
  end
end
```

**Step 4: Run tests**

```bash
mix test test/ex_calibur/quest_runner_test.exs
```

Expected: all passing.

**Step 5: Commit**

```bash
git add lib/ex_calibur/quest_runner.ex test/ex_calibur/quest_runner_test.exs
git commit -m "feat: add QuestRunner with multi-step roster evaluation and escalation"
```

---

## Task 3: Wire QuestsLive to use QuestRunner

**Files:**
- Modify: `lib/ex_calibur_web/live/quests_live.ex`

**Step 1: Replace Evaluator.evaluate call with QuestRunner.run**

In `QuestsLive.handle_event("run_quest", ...)`, update the `Task.start` block:

```elixir
Task.start(fn ->
  result = ExCalibur.QuestRunner.run(quest, input)
  send(self(), {:quest_run_complete, run_id, quest_run.id, result})
end)
```

Also send `self()` correctly — the task needs the parent PID:

```elixir
parent = self()
Task.start(fn ->
  result = ExCalibur.QuestRunner.run(quest, input)
  send(parent, {:quest_run_complete, run_id, quest_run.id, result})
end)
```

**Step 2: Update result display to show trace**

In `quest_card` component, update the run result display block:

```elixir
<%= if @run_state do %>
  <div class={["rounded p-3 text-sm", run_state_class(@run_state.status)]}>
    <div class="font-medium">{String.capitalize(@run_state.status)}</div>
    <%= if result = @run_state.result do %>
      <div class="mt-1 font-semibold">
        {String.upcase(result[:verdict] || "")}
        <span class="font-normal text-xs ml-1">
          {if result[:confidence], do: "#{Float.round(result.confidence * 100)}% confidence"}
        </span>
      </div>
      <%= if trace = result[:trace] do %>
        <div class="mt-2 space-y-1">
          <%= for {step_result, idx} <- Enum.with_index(trace) do %>
            <div class="text-xs text-muted-foreground">
              Step {idx + 1}: {step_result.verdict} ({step_result.step["who"]})
              <%= if idx < length(trace) - 1 do %>
                <span class="ml-1 text-amber-600">↑ escalated</span>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    <% end %>
  </div>
<% end %>
```

**Step 3: Compile and run tests**

```bash
mix compile --warnings-as-errors && mix test test/ex_calibur_web/live/quests_live_test.exs
```

Expected: all passing.

**Step 4: Commit**

```bash
git add lib/ex_calibur_web/live/quests_live.ex
git commit -m "feat: wire QuestsLive to QuestRunner, show escalation trace"
```

---

## Task 4: Add escalation config to quest roster UI

**Files:**
- Modify: `lib/ex_calibur_web/live/quests_live.ex`

**Step 1: Add Claude tier options to the "Who runs it" dropdown in new_quest_form**

```elixir
<select name="quest[who]" class="w-full text-sm border rounded px-2 py-1 bg-background">
  <option value="all">Everyone</option>
  <option value="apprentice">Apprentice tier</option>
  <option value="journeyman">Journeyman tier</option>
  <option value="master">Master tier</option>
  <optgroup label="Cloud (escalation)">
    <option value="claude_haiku">Claude Haiku</option>
    <option value="claude_sonnet">Claude Sonnet</option>
    <option value="claude_opus">Claude Opus</option>
  </optgroup>
</select>
```

**Step 2: Add escalate_on to create_quest event handler**

In `handle_event("create_quest", ...)`, add `escalate_on` to the roster step:

```elixir
roster = [
  %{
    "who" => params["who"] || "all",
    "when" => "on_trigger",
    "how" => params["how"] || "consensus",
    "escalate_on" => build_escalate_on(params["escalate_on_type"], params["escalate_on_value"])
  }
]
```

Add private helper:

```elixir
defp build_escalate_on("verdict", value), do: %{"type" => "verdict", "values" => String.split(value, ",")}
defp build_escalate_on("confidence", value) do
  case Float.parse(value || "") do
    {threshold, _} -> %{"type" => "confidence", "threshold" => threshold}
    :error -> "never"
  end
end
defp build_escalate_on("always", _), do: "always"
defp build_escalate_on(_, _), do: "never"
```

**Step 3: Compile check and run full suite**

```bash
mix compile --warnings-as-errors && mix test
```

Expected: all passing.

**Step 4: Commit**

```bash
git add lib/ex_calibur_web/live/quests_live.ex
git commit -m "feat: add Claude tier options and escalate_on to quest roster UI"
```

---

## Task 5: Add ANTHROPIC_API_KEY to config

**Files:**
- Modify: `config/runtime.exs`
- Modify: `config/dev.exs`

**Step 1: Add to runtime.exs**

```elixir
config :ex_calibur, :anthropic_api_key,
  System.get_env("ANTHROPIC_API_KEY")
```

**Step 2: Add to dev.exs (optional, with comment)**

```elixir
# config :ex_calibur, :anthropic_api_key, "sk-ant-..."
```

**Step 3: Update docker-compose.yml** — add env var pass-through:

```yaml
environment:
  - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
```

**Step 4: Compile check**

```bash
mix compile --warnings-as-errors
```

**Step 5: Commit**

```bash
git add config/runtime.exs config/dev.exs docker-compose.yml
git commit -m "feat: add ANTHROPIC_API_KEY config for Claude escalation"
```

---

## Task 6: Format, full test run, final commit

**Step 1: Format**

```bash
mix format
```

**Step 2: Full test suite**

```bash
mix test
```

Expected: all passing.

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: escalation complete — quest rosters chain across Ollama and Claude tiers"
```
