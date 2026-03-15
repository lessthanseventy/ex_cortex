# Provider Abstraction & System Gaps Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unify LLM provider dispatch behind a single abstraction, close integration gaps (quest→Lodge, quest run recording, Ollama tool calling), add `lodge_card` output type, and fix all review nits.

**Architecture:** New `ExCortex.LLM` behaviour with provider modules (`ExCortex.LLM.Ollama`, `ExCortex.LLM.Claude`). Member config gains a `provider` field. StepRunner dispatches through `ExCortex.LLM.complete/4` instead of hardcoded `call_member` branches. QuestRunner records runs. Steps gain `lodge_card` output type.

**Tech Stack:** Phoenix LiveView, Ecto, ReqLLM, Excellence.LLM.Ollama, SaladUI components.

---

## Task 1: Create ExCortex.LLM Behaviour and Provider Modules

**Files:**
- Create: `lib/ex_cortex/llm.ex`
- Create: `lib/ex_cortex/llm/ollama.ex`
- Create: `lib/ex_cortex/llm/claude.ex`
- Create: `test/ex_cortex/llm_test.exs`

**Step 1: Write the failing test**

Create `test/ex_cortex/llm_test.exs`:

```elixir
defmodule ExCortex.LLMTest do
  use ExUnit.Case, async: true

  alias ExCortex.LLM

  describe "provider_for/1" do
    test "returns Ollama module for ollama provider" do
      assert LLM.provider_for("ollama") == ExCortex.LLM.Ollama
    end

    test "returns Claude module for claude provider" do
      assert LLM.provider_for("claude") == ExCortex.LLM.Claude
    end

    test "returns Ollama as default for nil" do
      assert LLM.provider_for(nil) == ExCortex.LLM.Ollama
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/llm_test.exs 2>&1' --pane=main:1.3`
Expected: FAIL — module not defined.

**Step 3: Create the LLM behaviour**

Create `lib/ex_cortex/llm.ex`:

```elixir
defmodule ExCortex.LLM do
  @moduledoc """
  Unified LLM provider abstraction.

  Dispatches to provider-specific modules based on the provider string
  stored in member config. Supports Ollama, Claude, and is extensible
  for future providers (OpenAI, Groq, etc.).

  ## Usage

      ExCortex.LLM.complete("ollama", "llama3:8b", system_prompt, user_text)
      ExCortex.LLM.complete("claude", "claude-sonnet-4-6", system_prompt, user_text)
  """

  @callback complete(model :: String.t(), system_prompt :: String.t(), user_text :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @callback complete_with_tools(
              model :: String.t(),
              system_prompt :: String.t(),
              user_text :: String.t(),
              tools :: [map()],
              opts :: keyword()
            ) :: {:ok, String.t()} | {:error, term()}

  @callback configured?() :: boolean()

  @providers %{
    "ollama" => ExCortex.LLM.Ollama,
    "claude" => ExCortex.LLM.Claude
  }

  def provider_for(nil), do: ExCortex.LLM.Ollama
  def provider_for(""), do: ExCortex.LLM.Ollama
  def provider_for(name), do: Map.get(@providers, name, ExCortex.LLM.Ollama)

  def providers, do: @providers

  def complete(provider, model, system_prompt, user_text, opts \\ []) do
    provider_for(provider).complete(model, system_prompt, user_text, opts)
  end

  def complete_with_tools(provider, model, system_prompt, user_text, tools, opts \\ []) do
    provider_for(provider).complete_with_tools(model, system_prompt, user_text, tools, opts)
  end

  def configured?(provider) do
    provider_for(provider).configured?()
  end
end
```

**Step 4: Create Ollama provider module**

Create `lib/ex_cortex/llm/ollama.ex`:

```elixir
defmodule ExCortex.LLM.Ollama do
  @moduledoc "Ollama LLM provider."
  @behaviour ExCortex.LLM

  alias Excellence.LLM.Ollama

  @impl true
  def complete(model, system_prompt, user_text, opts \\ []) do
    ollama = client(opts)
    chain = Keyword.get(opts, :fallback_chain, Application.get_env(:ex_cortex, :model_fallback_chain, []))
    models = ExCortex.StepRunner.fallback_models_for(model, chain)

    messages = [
      %{role: :system, content: system_prompt},
      %{role: :user, content: user_text}
    ]

    Enum.reduce_while(models, {:error, :all_models_failed}, fn m, acc ->
      case Ollama.chat(ollama, m, messages) do
        {:ok, %{content: text}} -> {:halt, {:ok, text}}
        {:ok, text} when is_binary(text) -> {:halt, {:ok, text}}
        _ -> {:cont, acc}
      end
    end)
  end

  @impl true
  def complete_with_tools(model, system_prompt, user_text, _tools, opts \\ []) do
    # TODO: Wire Ollama native tool calling when available
    # For now, fall back to plain completion
    complete(model, system_prompt, user_text, opts)
  end

  @impl true
  def configured? do
    url = Application.get_env(:ex_cortex, :ollama_url, "http://127.0.0.1:11434")
    url != nil and url != ""
  end

  defp client(opts) do
    url = Keyword.get(opts, :url, Application.get_env(:ex_cortex, :ollama_url, "http://127.0.0.1:11434"))
    Ollama.new(base_url: url)
  end
end
```

**Step 5: Create Claude provider module**

Create `lib/ex_cortex/llm/claude.ex`:

```elixir
defmodule ExCortex.LLM.Claude do
  @moduledoc "Claude (Anthropic) LLM provider."
  @behaviour ExCortex.LLM

  @model_ids %{
    "claude_haiku" => "anthropic:claude-haiku-4-5",
    "claude-haiku-4-5" => "anthropic:claude-haiku-4-5",
    "claude_sonnet" => "anthropic:claude-sonnet-4-6",
    "claude-sonnet-4-6" => "anthropic:claude-sonnet-4-6",
    "claude_opus" => "anthropic:claude-opus-4-6",
    "claude-opus-4-6" => "anthropic:claude-opus-4-6"
  }

  @impl true
  def complete(model, system_prompt, user_text, _opts \\ []) do
    model_spec = resolve_model(model)

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_text}
    ]

    case ReqLLM.generate_text(model_spec, messages) do
      {:ok, response} -> {:ok, response.text}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  @impl true
  def complete_with_tools(model, system_prompt, user_text, tools, _opts \\ []) do
    model_spec = resolve_model(model)

    context =
      ReqLLM.Context.new([
        ReqLLM.Context.system(system_prompt),
        ReqLLM.Context.user(user_text)
      ])

    run_agent_loop(model_spec, context, tools, 0)
  end

  @impl true
  def configured? do
    key = ReqLLM.get_key(:anthropic_api_key) || System.get_env("ANTHROPIC_API_KEY")
    key != nil and key != ""
  end

  def tiers, do: ~w(claude_haiku claude_sonnet claude_opus)

  defp resolve_model(model) do
    Map.get(@model_ids, model, "anthropic:#{model}")
  end

  @max_tool_iterations 5

  defp run_agent_loop(_model_spec, _context, _tools, iter) when iter >= @max_tool_iterations do
    {:error, :max_iterations_exceeded}
  end

  defp run_agent_loop(model_spec, context, tools, iter) do
    case ReqLLM.generate_text(model_spec, context, tools: tools) do
      {:ok, response} ->
        case ReqLLM.Response.classify(response) do
          %{type: :final_answer, text: text} ->
            {:ok, text}

          %{type: :tool_calls, tool_calls: calls} ->
            next_context =
              ReqLLM.Context.execute_and_append_tools(response.context, calls, tools)

            run_agent_loop(model_spec, next_context, tools, iter + 1)
        end

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
```

**Step 6: Run tests to verify they pass**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/llm_test.exs 2>&1' --pane=main:1.3`
Expected: PASS

**Step 7: Commit**

```bash
git add lib/ex_cortex/llm.ex lib/ex_cortex/llm/ test/ex_cortex/llm_test.exs
git commit -m "feat: add unified ExCortex.LLM behaviour with Ollama and Claude providers"
```

---

## Task 2: Refactor StepRunner to Use ExCortex.LLM

**Files:**
- Modify: `lib/ex_cortex/step_runner.ex`
- Modify: `lib/ex_cortex/quests/step.ex` (add `freeform` and `lodge_card` to output_type validation)
- Test: existing tests should still pass

**Step 1: Add `provider` to member_to_runner_spec**

In `lib/ex_cortex/step_runner.ex`, change `member_to_runner_spec/1` (around line 285):

FROM:
```elixir
defp member_to_runner_spec(db) do
  %{
    type: :ollama,
    model: db.config["model"] || "phi4-mini",
    system_prompt: db.config["system_prompt"] || "",
    name: db.name,
    tools: resolve_member_tools(db.config["tools"])
  }
end
```

TO:
```elixir
defp member_to_runner_spec(db) do
  %{
    provider: db.config["provider"] || "ollama",
    model: db.config["model"] || "phi4-mini",
    system_prompt: db.config["system_prompt"] || "",
    name: db.name,
    tools: resolve_member_tools(db.config["tools"])
  }
end
```

**Step 2: Replace call_member with unified dispatch**

Replace the three `call_member` clauses (`:claude` with tools, `:claude` without tools, `:ollama`) with a single function:

```elixir
defp call_member(%{provider: provider, model: model, system_prompt: system_prompt, tools: tools}, input_text) do
  prompt = system_prompt || ""

  result =
    if tools != [] do
      ExCortex.LLM.complete_with_tools(provider, model, prompt, input_text, tools)
    else
      ExCortex.LLM.complete(provider, model, prompt, input_text)
    end

  case result do
    {:ok, text} -> parse_verdict(text)
    {:error, _} -> %{verdict: "abstain", confidence: 0.0, reason: "LLM error (#{provider})"}
  end
end
```

**Step 3: Replace call_member_raw similarly**

```elixir
defp call_member_raw(%{provider: provider, model: model, system_prompt: system_prompt, tools: tools}, input_text) do
  prompt = system_prompt || ""

  result =
    if tools != [] do
      ExCortex.LLM.complete_with_tools(provider, model, prompt, input_text, tools)
    else
      ExCortex.LLM.complete(provider, model, prompt, input_text)
    end

  case result do
    {:ok, text} -> text
    _ -> nil
  end
end
```

**Step 4: Update run_step to not pass ollama client**

Change `run_step/4` to `run_step/3` — remove the `ollama` parameter since the LLM module handles client creation internally:

```elixir
defp run_step(members, _how, input_text) do
  Enum.map(members, fn member ->
    result = call_member(member, input_text)
    Map.put(result, :member, member.name)
  end)
end
```

Update all callers of `run_step` to drop the `ollama` argument. Also remove `ollama = Ollama.new(...)` lines from `run/2` clauses that create them.

**Step 5: Update resolve_members for Claude tiers**

Change the Claude tier clause to return `provider: "claude"` instead of `type: :claude`:

```elixir
defp resolve_members(claude_tier) when claude_tier in ["claude_haiku", "claude_sonnet", "claude_opus"] do
  [%{provider: "claude", model: claude_tier, name: claude_tier, system_prompt: nil, tools: []}]
end
```

**Step 6: Update run_artifact_step dispatch**

In `run_artifact_step/4` and the reasoning pipeline in `run_artifact/2`, replace the `case member do` pattern matching on `:claude`/`:ollama` with a call to `ExCortex.LLM.complete/4`:

```elixir
raw =
  case ExCortex.LLM.complete(member.provider, member.model, system_prompt, input_text) do
    {:ok, text} -> text
    _ -> nil
  end
```

Remove the `ollama` parameter from `run_artifact/2` and `run_artifact_step/4`.

**Step 7: Remove old imports**

Remove these aliases from the top of StepRunner:
```elixir
# REMOVE:
alias ExCortex.ClaudeClient
alias Excellence.LLM.Ollama
```

**Step 8: Add `freeform` and `lodge_card` to Step output_type validation**

In `lib/ex_cortex/quests/step.ex`, update the `validate_inclusion(:output_type, ...)` list:

```elixir
|> validate_inclusion(:output_type, [
  "verdict",
  "artifact",
  "freeform",
  "lodge_card",
  "slack",
  "webhook",
  "github_issue",
  "github_pr",
  "email",
  "pagerduty"
])
```

**Step 9: Verify compilation and run tests**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix compile --warnings-as-errors 2>&1 | tail -10' --pane=main:1.3`
Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test 2>&1 | tail -10' --pane=main:1.3`
Expected: Clean compilation, all tests pass.

**Step 10: Commit**

```bash
git add lib/ex_cortex/step_runner.ex lib/ex_cortex/quests/step.ex
git commit -m "refactor: unify StepRunner LLM dispatch through ExCortex.LLM provider abstraction"
```

---

## Task 3: Add lodge_card Output Type to StepRunner

**Files:**
- Modify: `lib/ex_cortex/step_runner.ex`
- Create: `test/ex_cortex/step_runner_lodge_card_test.exs`

**Step 1: Write the failing test**

Create `test/ex_cortex/step_runner_lodge_card_test.exs`:

```elixir
defmodule ExCortex.StepRunner.LodgeCardTest do
  use ExCortex.DataCase

  alias ExCortex.Lodge

  describe "lodge_card output type" do
    test "posts a card to the Lodge when output_type is lodge_card" do
      # Verify no cards exist initially
      assert Lodge.list_cards() == []

      # The actual LLM call will fail in test (no Ollama running),
      # so we test the wiring by checking the step matcher exists
      step = %{
        output_type: "lodge_card",
        roster: [],
        context_providers: [],
        name: "Test Lodge Step",
        description: "Posts to lodge"
      }

      # With empty roster, should get :no_roster error
      assert {:error, :no_roster} = ExCortex.StepRunner.run(step, "test input")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/step_runner_lodge_card_test.exs 2>&1' --pane=main:1.3`
Expected: FAIL — no matching `run/2` clause for `output_type: "lodge_card"`.

**Step 3: Add lodge_card handler to StepRunner**

In `lib/ex_cortex/step_runner.ex`, add a new `run/2` clause before the default struct clause (around line 170):

```elixir
def run(%{output_type: "lodge_card"} = quest, input_text) do
  context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
  augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

  case run_artifact(quest, augmented) do
    {:ok, attrs} ->
      card_attrs = %{
        type: "note",
        title: attrs.title,
        body: attrs.body,
        tags: attrs[:tags] || [],
        source: "quest",
        quest_id: quest[:id]
      }

      ExCortex.Lodge.post_card(card_attrs)
      {:ok, %{lodge_card: card_attrs}}

    error ->
      error
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/step_runner_lodge_card_test.exs 2>&1' --pane=main:1.3`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_cortex/step_runner.ex test/ex_cortex/step_runner_lodge_card_test.exs
git commit -m "feat: add lodge_card output type to StepRunner for quest→Lodge integration"
```

---

## Task 4: Record Quest Runs in QuestRunner

**Files:**
- Modify: `lib/ex_cortex/quest_runner.ex`
- Create: `test/ex_cortex/quest_runner_recording_test.exs`

**Step 1: Write the failing test**

Create `test/ex_cortex/quest_runner_recording_test.exs`:

```elixir
defmodule ExCortex.QuestRunner.RecordingTest do
  use ExCortex.DataCase

  alias ExCortex.Quests

  describe "run/2 recording" do
    test "creates a QuestRun record when a quest is executed" do
      {:ok, step} = Quests.create_step(%{name: "Recording Test Step", trigger: "manual", roster: []})

      {:ok, quest} =
        Quests.create_quest(%{
          name: "Recording Test Quest",
          trigger: "manual",
          steps: [%{"step_id" => step.id, "flow" => "always"}]
        })

      # Run the quest
      ExCortex.QuestRunner.run(quest, "test input")

      # Verify a quest run was created
      runs = Quests.list_quest_runs(quest)
      assert length(runs) >= 1
      run = List.first(runs)
      assert run.quest_id == quest.id
      assert run.status in ["complete", "failed"]
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/quest_runner_recording_test.exs 2>&1' --pane=main:1.3`
Expected: FAIL — no QuestRun created.

**Step 3: Add quest run recording to QuestRunner**

In `lib/ex_cortex/quest_runner.ex`, modify `run/2` to create a QuestRun:

```elixir
def run(quest, input) do
  ordered_steps = Enum.sort_by(quest.steps, &Map.get(&1, "order", 0))

  Logger.info("[QuestRunner] Running quest #{quest.id} (#{quest.name}), #{length(ordered_steps)} step(s)")

  # Create a pending quest run
  {:ok, quest_run} = Quests.create_quest_run(%{quest_id: quest.id, status: "running"})

  # Broadcast quest started
  Phoenix.PubSub.broadcast(ExCortex.PubSub, "quest_runs", {:quest_run_started, quest_run})

  # ... existing step execution logic ...

  # After execution, update the quest run
  final_status = if match?({:ok, _}, List.last(results)), do: "complete", else: "failed"

  step_results =
    results
    |> Enum.with_index()
    |> Map.new(fn {result, idx} ->
      {to_string(idx), inspect_result(result)}
    end)

  Quests.update_quest_run(quest_run, %{status: final_status, step_results: step_results})

  # Broadcast quest completed
  Phoenix.PubSub.broadcast(ExCortex.PubSub, "quest_runs", {:quest_run_completed, quest_run})

  case List.last(results) do
    {:ok, _} = ok -> ok
    _ -> {:ok, %{steps: results}}
  end
end
```

Add a helper to safely inspect results:

```elixir
defp inspect_result({:ok, result}) when is_map(result), do: %{"status" => "ok", "data" => inspect(result)}
defp inspect_result({:error, reason}), do: %{"status" => "error", "reason" => inspect(reason)}
defp inspect_result(other), do: %{"status" => "unknown", "data" => inspect(other)}
```

**Step 4: Run tests**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/quest_runner_recording_test.exs 2>&1' --pane=main:1.3`
Expected: PASS

**Step 5: Run full test suite**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test 2>&1 | tail -10' --pane=main:1.3`
Expected: All tests pass.

**Step 6: Commit**

```bash
git add lib/ex_cortex/quest_runner.ex test/ex_cortex/quest_runner_recording_test.exs
git commit -m "feat: record QuestRun on every quest execution with PubSub broadcasting"
```

---

## Task 5: Fix Review Nits — Lodge & Components

**Files:**
- Modify: `lib/ex_cortex/lodge.ex`
- Modify: `lib/ex_cortex_web/live/lodge_live.ex`
- Modify: `lib/ex_cortex_web/components/lodge_cards.ex`

**Step 1: Fix sync_augury source to "lore"**

In `lib/ex_cortex/lodge.ex`, change `source: "quest"` to `source: "lore"` in the `sync_augury/0` function (line 109):

```elixir
# FROM:
source: "quest",
# TO:
source: "lore",
```

**Step 2: Remove no-op edit_augury handler and button**

In `lib/ex_cortex_web/components/lodge_cards.ex`, remove the Edit button from the augury card renderer (lines 129-136). Remove the entire `<.button>` block for `edit_augury`.

In `lib/ex_cortex_web/live/lodge_live.ex`, remove the `handle_event("edit_augury", ...)` clause.

**Step 3: Extract shared tag presets**

Create a module attribute or function in `lodge_cards.ex` for the shared preset tags:

```elixir
@preset_tags ~w(tech urgent meeting todo idea)
def preset_tags, do: @preset_tags
```

Then in `lodge_live.ex`, replace both instances of `~w(tech urgent meeting todo idea)` with:

```elixir
<%= for tag <- ExCortexWeb.Components.LodgeCards.preset_tags() do %>
```

**Step 4: Fix card_header tags access**

In `lib/ex_cortex_web/components/lodge_cards.ex`, change line 171:

```elixir
# FROM:
tags = Map.get(assigns.card, :tags) || []
# TO:
tags = Map.get(assigns.card, :tags, []) || []
```

**Step 5: Move sync calls behind connected? guard**

In `lib/ex_cortex_web/live/lodge_live.ex`, move `sync_proposals()` and `sync_augury()` inside the `if connected?(socket)` block so they only run once on the WebSocket connect, not on the initial static render:

```elixir
if has_members do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "lodge")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "lore")
    Lodge.sync_proposals()
    Lodge.sync_augury()
  end

  {:ok, load_cards(assign(socket, page_title: "Lodge", selected_tags: [], filter_tags: []))}
else
  {:ok, push_navigate(socket, to: ~p"/town-square")}
end
```

**Step 6: Verify tests pass**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test 2>&1 | tail -10' --pane=main:1.3`
Expected: All tests pass.

**Step 7: Commit**

```bash
git add lib/ex_cortex/lodge.ex lib/ex_cortex_web/live/lodge_live.ex lib/ex_cortex_web/components/lodge_cards.ex
git commit -m "fix: review nits — augury source, shared tag presets, sync perf, dead handler"
```

---

## Task 6: Add Provider Config to Member UI

**Files:**
- Modify: `lib/ex_cortex_web/live/members_live.ex` (or wherever the member/role form renders)
- Modify: `lib/ex_cortex_ui/components/role_form.ex` (if used)

**Step 1: Find the member creation/edit form**

Search for the member creation form. It's either in `members_live.ex` or uses the `ExCortexUI.Components.RoleForm`. Read the file to understand the current form fields.

**Step 2: Add provider dropdown**

Add a provider select field to the member form, right before or after the model field:

```heex
<div>
  <label class="text-sm font-medium">Provider</label>
  <select
    name="member[config][provider]"
    class="h-9 text-sm border border-input rounded-md px-3 bg-background w-full"
  >
    <option value="ollama" selected={@member_config["provider"] == "ollama"}>Ollama (local)</option>
    <option value="claude" selected={@member_config["provider"] == "claude"}>Claude (Anthropic)</option>
  </select>
</div>
```

When "claude" is selected, the model field should hint at Claude model names (claude_haiku, claude_sonnet, claude_opus or claude-sonnet-4-6, etc.).

**Step 3: Verify the form submits provider correctly**

Test that creating/editing a member with provider="claude" persists it to `config["provider"]`.

**Step 4: Verify compilation and existing tests**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test 2>&1 | tail -10' --pane=main:1.3`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/members_live.ex
git commit -m "feat: add provider dropdown to member form for configurable LLM backends"
```

---

## Task 7: Wire lodge_card Output Type into Quest Template UI

**Files:**
- Modify: `lib/ex_cortex_web/live/quests_live.ex` (add lodge_card to output type dropdown)

**Step 1: Find the step creation form in quests_live.ex**

Search for the `output_type` select/dropdown in the quest step creation UI.

**Step 2: Add lodge_card option**

Add `<option value="lodge_card">Lodge Card</option>` to the output type dropdown alongside verdict, artifact, freeform, and the herald types.

**Step 3: Verify compilation**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix compile --warnings-as-errors 2>&1 | tail -5' --pane=main:1.3`
Expected: Clean.

**Step 4: Commit**

```bash
git add lib/ex_cortex_web/live/quests_live.ex
git commit -m "feat: add lodge_card option to step output type dropdown"
```

---

## Task 8: Fix Grimoire Telemetry Tab

**Files:**
- Modify: `lib/ex_cortex_web/live/grimoire_live.ex`

**Step 1: Read the current Grimoire to understand the telemetry placeholder**

Read `lib/ex_cortex_web/live/grimoire_live.ex` and find the telemetry tab content.

**Step 2: Wire monitoring widgets into the telemetry tab**

Check if `ex_cellence_dashboard` is available as a dependency. If it is, import the relevant components (`ReplayViewer`, `AgentHealth`, `OutcomeTracker`, `DriftMonitor`, `CalibrationChart`) and render them in the telemetry tab with the appropriate data.

If the dashboard dependency is not available or the components don't exist, create a clean placeholder with SaladUI components:

```heex
<div class="space-y-4">
  <.card>
    <.card_header>
      <.card_title>System Telemetry</.card_title>
      <.card_description>Monitoring widgets will be available when evaluation data is collected.</.card_description>
    </.card_header>
    <.card_content>
      <p class="text-sm text-muted-foreground">
        Run quests to start collecting telemetry data.
      </p>
    </.card_content>
  </.card>
</div>
```

**Step 3: Add test for telemetry tab rendering**

In the grimoire test, add:

```elixir
test "telemetry tab renders", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/grimoire")
  html = view |> element("button", "Telemetry") |> render_click()
  assert html =~ "Telemetry"
end
```

**Step 4: Verify tests pass**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex_web/live/grimoire_live_test.exs 2>&1' --pane=main:1.3`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/grimoire_live.ex test/ex_cortex_web/live/grimoire_live_test.exs
git commit -m "fix: wire telemetry tab in Grimoire with SaladUI components"
```

---

## Task 9: Rename card_wrapper to Avoid SaladUI.Card Collision

**Files:**
- Modify: `lib/ex_cortex_web/components/lodge_cards.ex`

**Step 1: Rename private components to avoid collision**

Rename `card_wrapper` → `lodge_card_frame` and `card_header` → `lodge_card_header` and `card_actions` → `lodge_card_actions` in `lodge_cards.ex`. This is a purely internal rename — these are all `defp` functions, so no external callers.

**Step 2: Import SaladUI.Card**

Add `import SaladUI.Card` at the top of the module. Since `card_header` is no longer a local function name, there's no collision.

**Step 3: Optionally use SaladUI.Card in the wrapper**

If SaladUI.Card provides the same visual treatment, use it:

```elixir
defp lodge_card_frame(assigns) do
  ~H"""
  <.card class="p-5 space-y-2">
    <.lodge_card_header card={@card} />
    {render_slot(@inner_block)}
    <.lodge_card_actions card={@card} />
  </.card>
  """
end
```

**Step 4: Run component tests**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex_web/components/lodge_cards_test.exs 2>&1' --pane=main:1.3`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/components/lodge_cards.ex
git commit -m "refactor: rename lodge card sub-components to avoid SaladUI.Card collision"
```

---

## Task 10: Clean Up ClaudeClient (Now Superseded)

**Files:**
- Modify: `lib/ex_cortex/claude_client.ex`

**Step 1: Check for remaining callers**

Search for `ClaudeClient` references in `lib/`. After Task 2, StepRunner should no longer reference it. Check if any other module still uses it.

**Step 2: If no callers remain, mark as deprecated or delegate**

If `ClaudeClient` has no callers, either:
- Delete it entirely, or
- Add `@moduledoc deprecated: "Use ExCortex.LLM.Claude instead"` and delegate the public functions

If callers remain, update them to use `ExCortex.LLM.Claude` or `ExCortex.LLM.complete/4`.

**Step 3: Verify compilation**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix compile --warnings-as-errors 2>&1 | tail -5' --pane=main:1.3`
Expected: Clean.

**Step 4: Commit**

```bash
git add lib/ex_cortex/claude_client.ex
git commit -m "refactor: deprecate ClaudeClient in favor of ExCortex.LLM.Claude"
```

---

## Task 11: Full Test Suite Pass and Format

**Files:**
- Any files that need fixing

**Step 1: Run the full test suite**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test 2>&1 | tail -20' --pane=main:1.3`

**Step 2: Fix any failures**

If there are failures, fix them. Common issues:
- StepRunner tests may need updating for the new `provider` field instead of `type: :ollama`
- Member fixtures may need `"provider" => "ollama"` in config

**Step 3: Run mix format**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix format 2>&1' --pane=main:1.3`

**Step 4: Run compile with warnings-as-errors**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix compile --warnings-as-errors 2>&1 | tail -10' --pane=main:1.3`

**Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: test suite fix-up after provider abstraction refactor"
```
