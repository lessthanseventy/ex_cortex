# Tool Calling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add tool calling to members (agent loop) and steps (reflect + escalate modes), with a safe/YOLO tier split.

**Architecture:** Tools are `ReqLLM.Tool` structs (with callbacks) registered in our own module with a `safe?` tier. The registry returns `[%ReqLLM.Tool{}]` lists that are passed directly to `ReqLLM.generate_text/3` as `tools:`. The Claude agent loop uses `ReqLLM.Response.classify/1` to detect tool calls and `ReqLLM.Context.execute_and_append_tools/3` to execute and thread results — no manual HTTP or message building. StepRunner gains reflect and escalate phases that wrap the existing roster run.

**Tech Stack:** Elixir/OTP, ReqLLM (native tool calling, Context, Response), Excellence.LLM.Ollama, ExCortex.Lore, ExCortex.Quests

---

## Task 1: Tool registry using ReqLLM.Tool

**Files:**
- Create: `lib/ex_cortex/tools/registry.ex`
- Create: `lib/ex_cortex/tools/query_lore.ex`
- Create: `lib/ex_cortex/tools/run_quest.ex`
- Create: `lib/ex_cortex/tools/fetch_url.ex`
- Create: `test/ex_cortex/tools/registry_test.exs`

We use `ReqLLM.Tool` as the tool struct — it handles parameter schema compilation, Anthropic/Ollama format conversion, and callback execution. Our registry adds only the `safe?` tier that ReqLLM doesn't have.

**Step 1: Write the failing test**

```elixir
# test/ex_cortex/tools/registry_test.exs
defmodule ExCortex.Tools.RegistryTest do
  use ExUnit.Case, async: true

  alias ExCortex.Tools.Registry

  test "list_safe/0 returns ReqLLM.Tool structs for safe tools only" do
    tools = Registry.list_safe()
    assert Enum.all?(tools, &match?(%ReqLLM.Tool{}, &1))
    names = Enum.map(tools, & &1.name)
    assert "query_lore" in names
    assert "run_quest" in names
    refute "fetch_url" in names
  end

  test "list_yolo/0 returns all tools including unsafe" do
    tools = Registry.list_yolo()
    names = Enum.map(tools, & &1.name)
    assert "query_lore" in names
    assert "fetch_url" in names
  end

  test "get/1 returns a ReqLLM.Tool by name" do
    assert %ReqLLM.Tool{name: "query_lore"} = Registry.get("query_lore")
  end

  test "get/1 returns nil for unknown tool" do
    assert nil == Registry.get("does_not_exist")
  end

  test "resolve_tools/1 with :all_safe returns safe tools" do
    tools = Registry.resolve_tools(:all_safe)
    names = Enum.map(tools, & &1.name)
    assert "query_lore" in names
    refute "fetch_url" in names
  end

  test "resolve_tools/1 with :yolo returns all tools" do
    tools = Registry.resolve_tools(:yolo)
    names = Enum.map(tools, & &1.name)
    assert "fetch_url" in names
  end

  test "resolve_tools/1 with list of names returns matching tools" do
    tools = Registry.resolve_tools(["query_lore"])
    assert length(tools) == 1
    assert hd(tools).name == "query_lore"
  end
end
```

**Step 2: Run test to verify it fails**

```bash
tmux-cli send 'mix test test/ex_cortex/tools/registry_test.exs 2>&1 | tail -5' --pane=main:1.3
```

Expected: compilation error (modules don't exist)

**Step 3: Create tool modules using ReqLLM.Tool.new!**

```elixir
# lib/ex_cortex/tools/query_lore.ex
defmodule ExCortex.Tools.QueryLore do
  @moduledoc "Tool: search lore entries by tags."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "query_lore",
      description: "Search the lore store for entries matching the given tags. Returns recent matching entries.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "tags" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "Tags to filter by"},
          "limit" => %{"type" => "integer", "description" => "Max entries to return (default 5)"}
        },
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(%{"tags" => tags} = input) do
    limit = Map.get(input, "limit", 5)
    entries = ExCortex.Lore.list_entries(tags: tags) |> Enum.take(limit)
    summaries = Enum.map(entries, fn e -> "#{e.title}: #{String.slice(e.body || "", 0, 200)}" end)
    {:ok, Enum.join(summaries, "\n---\n")}
  end

  def call(input), do: call(Map.put_new(input, "tags", []))
end
```

```elixir
# lib/ex_cortex/tools/run_quest.ex
defmodule ExCortex.Tools.RunQuest do
  @moduledoc "Tool: run a quest by name with a given input string."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "run_quest",
      description: "Run a named quest with the given input text. Returns the quest result.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "quest_name" => %{"type" => "string", "description" => "The name of the quest to run"},
          "input" => %{"type" => "string", "description" => "The input text to pass to the quest"}
        },
        "required" => ["quest_name", "input"]
      },
      callback: &call/1
    )
  end

  def call(%{"quest_name" => name, "input" => input}) do
    import Ecto.Query
    alias ExCortex.Repo
    alias ExCortex.Quests.Quest

    case Repo.one(from q in Quest, where: q.name == ^name, limit: 1) do
      nil -> {:error, "Quest '#{name}' not found"}
      quest ->
        preloaded = Repo.preload(quest, :steps)
        case ExCortex.QuestRunner.run(preloaded, input) do
          {:ok, result} -> {:ok, inspect(result)}
          {:error, reason} -> {:error, inspect(reason)}
        end
    end
  end
end
```

```elixir
# lib/ex_cortex/tools/fetch_url.ex
defmodule ExCortex.Tools.FetchUrl do
  @moduledoc "Tool (YOLO): fetch the body of a URL."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "fetch_url",
      description: "Fetch the text content of a URL. Only use when explicitly permitted.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "url" => %{"type" => "string", "description" => "The URL to fetch"}
        },
        "required" => ["url"]
      },
      callback: &call/1
    )
  end

  def call(%{"url" => url}) do
    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, String.slice(body, 0, 4000)}
      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}
      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end
end
```

**Step 4: Create Registry**

```elixir
# lib/ex_cortex/tools/registry.ex
defmodule ExCortex.Tools.Registry do
  @moduledoc """
  Registry of available tools, tiered by safety.

  Returns `ReqLLM.Tool` structs — pass them directly to
  `ReqLLM.generate_text(model, context, tools: tools)`.

  Usage:
    Registry.list_safe()              # safe tools only
    Registry.list_yolo()              # all tools
    Registry.get("query_lore")        # single tool by name
    Registry.resolve_tools(:all_safe) # from step/member config
  """

  @safe_entries [
    ExCortex.Tools.QueryLore,
    ExCortex.Tools.RunQuest
  ]

  @yolo_entries [
    ExCortex.Tools.FetchUrl
  ]

  def list_safe, do: Enum.map(@safe_entries, & &1.req_llm_tool())

  def list_yolo, do: list_safe() ++ Enum.map(@yolo_entries, & &1.req_llm_tool())

  def get(name) when is_binary(name) do
    Enum.find(list_yolo(), &(&1.name == name))
  end

  @doc """
  Resolve a tools config value to a list of ReqLLM.Tool structs.

  Accepts:
  - :all_safe        — all safe tools
  - :yolo            — all tools (safe + yolo)
  - list of names    — specific tools by name
  - nil / []         — empty list
  """
  def resolve_tools(nil), do: []
  def resolve_tools([]), do: []
  def resolve_tools(:all_safe), do: list_safe()
  def resolve_tools(:yolo), do: list_yolo()

  def resolve_tools(names) when is_list(names) do
    Enum.flat_map(names, fn name ->
      case get(name) do
        nil -> []
        tool -> [tool]
      end
    end)
  end
end
```

**Step 5: Run tests**

```bash
tmux-cli send 'mix test test/ex_cortex/tools/registry_test.exs 2>&1 | tail -5' --pane=main:1.3
```

Expected: all pass

**Step 6: Commit**

```bash
tmux-cli send 'git add lib/ex_cortex/tools/ test/ex_cortex/tools/ && git commit -m "feat: add tool registry using ReqLLM.Tool with safe/yolo tier"' --pane=main:1.3
```

---

## Task 2: Claude agent loop using ReqLLM natively

**Files:**
- Modify: `lib/ex_cortex/claude_client.ex`
- Create: `test/ex_cortex/tools/claude_agent_loop_test.exs`

ReqLLM handles the entire multi-turn loop: `generate_text` passes tools to the model, `Response.classify` detects tool calls vs final answer, `Context.execute_and_append_tools` runs the tools and threads results back. No manual HTTP or message building needed.

**Step 1: Write the failing test**

```elixir
# test/ex_cortex/tools/claude_agent_loop_test.exs
defmodule ExCortex.ClaudeAgentLoopTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.ClaudeClient

  test "complete_with_tools/4 returns {:error, _} or {:ok, _} — does not crash without API key" do
    result = ClaudeClient.complete_with_tools("claude_haiku", "You are helpful", "Say hi", [])
    assert match?({:error, _}, result) or match?({:ok, _}, result)
  end

  test "complete_with_tools/4 returns {:error, _} for unknown tier" do
    result = ClaudeClient.complete_with_tools("claude_blorp", "sys", "msg", [])
    assert {:error, _} = result
  end
end
```

**Step 2: Run to verify it fails**

```bash
tmux-cli send 'mix test test/ex_cortex/tools/claude_agent_loop_test.exs 2>&1 | tail -5' --pane=main:1.3
```

**Step 3: Add `complete_with_tools/4` to ClaudeClient**

Add to `lib/ex_cortex/claude_client.ex`:

```elixir
  @max_tool_iterations 5

  @doc """
  Run a multi-turn agent loop using ReqLLM's native tool calling.

  - `tier` — "claude_haiku" | "claude_sonnet" | "claude_opus"
  - `system_prompt` — system prompt string
  - `user_text` — initial user message
  - `tools` — list of %ReqLLM.Tool{} structs (from ExCortex.Tools.Registry)

  Returns {:ok, text} on final answer or {:error, reason} on failure.
  """
  def complete_with_tools(tier, system_prompt, user_text, tools) do
    case Map.fetch(@model_ids, tier) do
      :error -> {:error, "unknown tier: #{tier}"}
      {:ok, model_spec} ->
        context =
          ReqLLM.Context.new([
            ReqLLM.Context.system(system_prompt),
            ReqLLM.Context.user(user_text)
          ])

        run_agent_loop(model_spec, context, tools, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # Private — agent loop
  # ---------------------------------------------------------------------------

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
            next_context = ReqLLM.Context.execute_and_append_tools(response.context, calls, tools)
            run_agent_loop(model_spec, next_context, tools, iter + 1)
        end

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end
```

**Step 4: Run tests**

```bash
tmux-cli send 'mix test test/ex_cortex/tools/claude_agent_loop_test.exs 2>&1 | tail -5' --pane=main:1.3
```

**Step 5: Run full suite**

```bash
tmux-cli send 'mix test 2>&1 | tail -5' --pane=main:1.3
```

**Step 6: Commit**

```bash
tmux-cli send 'git add lib/ex_cortex/claude_client.ex test/ex_cortex/tools/claude_agent_loop_test.exs && git commit -m "feat: add Claude agent loop via ReqLLM native tool calling"' --pane=main:1.3
```

---

## Task 3: Wire tools into StepRunner member calls

**Files:**
- Modify: `lib/ex_cortex/step_runner.ex`

Members now carry a `tools` config key. When tools are present, `call_member` uses `ClaudeClient.complete_with_tools` (which takes `[%ReqLLM.Tool{}]`). When absent, falls through to the existing single-shot path.

**Step 1: Update `member_to_runner_spec/1` to resolve tools at spec-build time**

In `step_runner.ex`, find `member_to_runner_spec/1` and update:

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

  # Resolve tools config string/list to [%ReqLLM.Tool{}] at spec-build time.
  defp resolve_member_tools(nil), do: []
  defp resolve_member_tools("all_safe"), do: ExCortex.Tools.Registry.resolve_tools(:all_safe)
  defp resolve_member_tools("yolo"), do: ExCortex.Tools.Registry.resolve_tools(:yolo)
  defp resolve_member_tools(names) when is_list(names), do: ExCortex.Tools.Registry.resolve_tools(names)
  defp resolve_member_tools(_), do: []
```

Also update the Claude tier spec builders to carry tools:

```elixir
  defp resolve_members(claude_tier) when claude_tier in ["claude_haiku", "claude_sonnet", "claude_opus"] do
    [%{type: :claude, tier: claude_tier, name: claude_tier, system_prompt: nil, tools: []}]
  end
```

**Step 2: Update `call_member/3` for Claude to dispatch to agent loop when tools present**

Find the existing `:claude` clause and split it:

```elixir
  defp call_member(%{type: :claude, tier: tier, system_prompt: system_prompt, tools: [_ | _] = tools}, input_text, _ollama) do
    prompt = system_prompt || default_claude_prompt()

    case ClaudeClient.complete_with_tools(tier, prompt, input_text, tools) do
      {:ok, text} -> parse_verdict(text)
      {:error, _} -> %{verdict: "abstain", confidence: 0.0, reason: "Claude agent loop error"}
    end
  end

  defp call_member(%{type: :claude, tier: tier, system_prompt: system_prompt}, input_text, _ollama) do
    prompt = system_prompt || default_claude_prompt()

    case ClaudeClient.complete(tier, prompt, input_text) do
      {:ok, text} -> parse_verdict(text)
      {:error, _} -> %{verdict: "abstain", confidence: 0.0, reason: "Claude API error"}
    end
  end
```

Do the same for `call_member_raw`:

```elixir
  defp call_member_raw(%{type: :claude, tier: tier, system_prompt: system_prompt, tools: [_ | _] = tools}, input_text, _ollama) do
    prompt = system_prompt || ""

    case ClaudeClient.complete_with_tools(tier, prompt, input_text, tools) do
      {:ok, text} -> text
      _ -> nil
    end
  end

  defp call_member_raw(%{type: :claude, tier: tier, system_prompt: system_prompt}, input_text, _ollama) do
    prompt = system_prompt || ""

    case ClaudeClient.complete(tier, prompt, input_text) do
      {:ok, text} -> text
      _ -> nil
    end
  end
```

**Step 3: Run full tests**

```bash
tmux-cli send 'mix test 2>&1 | tail -5' --pane=main:1.3
```

Expected: same pass count — no behaviour change for members without tools

**Step 4: Commit**

```bash
tmux-cli send 'git add lib/ex_cortex/step_runner.ex && git commit -m "feat: wire tool config into member runner specs and call_member dispatch"' --pane=main:1.3
```

---

## Task 4: Escalate mode in StepRunner

**Files:**
- Modify: `lib/ex_cortex/step_runner.ex`
- Modify: `test/ex_cortex/step_runner_test.exs`

**Step 1: Write the failing test**

Add to `test/ex_cortex/step_runner_test.exs`:

```elixir
  describe "escalate mode" do
    test "run/2 escalates from apprentice to journeyman when no apprentice members exist" do
      # No members in test DB — escalation falls through to empty result
      step = %Step{
        id: 99,
        name: "Escalate Test",
        output_type: "verdict",
        roster: [%{"who" => "apprentice", "how" => "solo", "when" => "sequential"}],
        escalate: true,
        escalate_threshold: 0.9,
        context_providers: []
      }

      # Should not crash even with no members — returns abstain, not error
      result = ExCortex.StepRunner.run(step, "test input")
      assert match?({:ok, %{verdict: _}}, result)
    end

    test "run/2 without escalate: true behaves as before" do
      step = %Step{
        id: 100,
        name: "No Escalate",
        output_type: "verdict",
        roster: [],
        escalate: false,
        context_providers: []
      }

      assert {:ok, %{verdict: "pass"}} = ExCortex.StepRunner.run(step, "test")
    end
  end
```

**Step 2: Run to verify it fails**

```bash
tmux-cli send 'mix test test/ex_cortex/step_runner_test.exs 2>&1 | tail -10' --pane=main:1.3
```

Expected: compile error (Step struct doesn't have escalate field yet, or function clause error)

**Step 3: Check the Step schema and add escalate fields**

```bash
tmux-cli send 'grep -n "field" lib/ex_cortex/quests/step.ex | head -30' --pane=main:1.3
```

Add to `lib/ex_cortex/quests/step.ex` schema (find the existing fields and add):

```elixir
    field :escalate, :boolean, default: false
    field :escalate_threshold, :float, default: 0.6
    field :escalate_on_verdict, {:array, :string}, default: []
```

Also add to `changeset/2` cast list:

```elixir
    |> cast(attrs, [...existing..., :escalate, :escalate_threshold, :escalate_on_verdict])
```

**Step 4: Add escalate logic to StepRunner**

The escalate logic wraps the existing `run/2` for roster lists. Add a new function head in `step_runner.ex` that handles structs with `escalate: true`:

```elixir
  # Escalate mode — try ranks in order until result is satisfying
  def run(%{escalate: true} = quest, input_text) do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    threshold = quest.escalate_threshold || 0.6
    escalate_on = quest.escalate_on_verdict || []

    Enum.reduce_while(["apprentice", "journeyman", "master"], nil, fn rank, _acc ->
      members = resolve_members(rank)

      if members == [] do
        {:cont, nil}
      else
        result = run(quest.roster, augmented)

        case result do
          {:ok, %{verdict: v, steps: steps}} = ok ->
            avg_confidence =
              steps
              |> Enum.flat_map(& &1.results)
              |> Enum.map(&Map.get(&1, :confidence, 0.5))
              |> then(fn [] -> 0.5; cs -> Enum.sum(cs) / length(cs) end)

            satisfied = avg_confidence >= threshold and v not in escalate_on

            if satisfied, do: {:halt, ok}, else: {:cont, ok}

          other ->
            {:cont, other}
        end
      end
    end)
    |> then(fn
      nil -> {:ok, %{verdict: "abstain", steps: []}}
      result -> result
    end)
  end
```

**Note:** Place this clause *before* the existing `def run(%{min_rank: ...} = quest, input_text)` clause so it pattern matches first.

**Step 5: Run escalate tests**

```bash
tmux-cli send 'mix test test/ex_cortex/step_runner_test.exs 2>&1 | tail -10' --pane=main:1.3
```

**Step 6: Run full suite**

```bash
tmux-cli send 'mix test 2>&1 | tail -5' --pane=main:1.3
```

**Step 7: Commit**

```bash
tmux-cli send 'git add lib/ex_cortex/quests/step.ex lib/ex_cortex/step_runner.ex test/ex_cortex/step_runner_test.exs && git commit -m "feat: add escalate mode to StepRunner — rank ladder with confidence threshold"' --pane=main:1.3
```

---

## Task 5: Reflect mode in StepRunner

**Files:**
- Modify: `lib/ex_cortex/step_runner.ex`
- Modify: `lib/ex_cortex/quests/step.ex`
- Modify: `test/ex_cortex/step_runner_test.exs`

**Step 1: Write the failing test**

Add to `test/ex_cortex/step_runner_test.exs`:

```elixir
  describe "reflect mode" do
    test "run/2 with loop_mode: reflect and no tools returns normal result" do
      step = %Step{
        id: 101,
        name: "Reflect Test",
        output_type: "verdict",
        roster: [],
        loop_mode: "reflect",
        loop_tools: [],
        reflect_threshold: 0.9,
        context_providers: []
      }

      # Empty roster → pass verdict, no reflect needed
      assert {:ok, %{verdict: "pass"}} = ExCortex.StepRunner.run(step, "test")
    end
  end
```

**Step 2: Run to verify it fails**

```bash
tmux-cli send 'mix test test/ex_cortex/step_runner_test.exs 2>&1 | tail -10' --pane=main:1.3
```

**Step 3: Add reflect fields to Step schema**

Add to `lib/ex_cortex/quests/step.ex`:

```elixir
    field :loop_mode, :string       # nil | "reflect" | "plan"
    field :loop_tools, {:array, :string}, default: []
    field :reflect_threshold, :float, default: 0.6
    field :reflect_on_verdict, {:array, :string}, default: []
    field :max_iterations, :integer, default: 3
```

Also add to `changeset/2` cast list.

**Step 4: Add reflect logic to StepRunner**

Add a clause before the escalate clause (reflect wraps the inner run, escalate wraps that):

```elixir
  # Reflect mode — run members, then if unsatisfied gather context via tools and retry
  def run(%{loop_mode: "reflect"} = quest, input_text) do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    threshold = quest.reflect_threshold || 0.6
    reflect_on = quest.reflect_on_verdict || []
    max_iter = quest.max_iterations || 3
    tools = ExCortex.Tools.Registry.resolve_tools(quest.loop_tools || [])

    do_reflect(quest, augmented, tools, threshold, reflect_on, max_iter, 0)
  end

  defp do_reflect(quest, input_text, _tools, _threshold, _reflect_on, max_iter, iter)
       when iter >= max_iter do
    run(quest.roster, input_text)
  end

  defp do_reflect(quest, input_text, tools, threshold, reflect_on, max_iter, iter) do
    result = run(quest.roster, input_text)

    case result do
      {:ok, %{verdict: v, steps: steps}} = ok ->
        avg_confidence =
          steps
          |> Enum.flat_map(& &1.results)
          |> Enum.map(&Map.get(&1, :confidence, 0.5))
          |> then(fn [] -> 0.5; cs -> Enum.sum(cs) / length(cs) end)

        satisfied = avg_confidence >= threshold and v not in reflect_on

        if satisfied or tools == [] do
          ok
        else
          # Ask tools for more context, then retry
          extra_context = gather_reflect_context(tools, input_text, v)
          augmented = "#{input_text}\n\n## Reflection Context\n#{extra_context}"
          do_reflect(quest, augmented, tools, threshold, reflect_on, max_iter, iter + 1)
        end

      other ->
        other
    end
  end

  defp gather_reflect_context(tools, _input_text, verdict) do
    # Use the first available tool to gather extra context.
    # ReqLLM.Tool.execute/2 runs the tool's callback with validated input.
    lore_tool = Enum.find(tools, &(&1.name == "query_lore"))

    if lore_tool do
      case ReqLLM.Tool.execute(lore_tool, %{"tags" => [], "limit" => 3}) do
        {:ok, content} -> "Prior lore context (verdict was #{verdict}):\n#{content}"
        _ -> ""
      end
    else
      tools
      |> Enum.map(fn tool ->
        case ReqLLM.Tool.execute(tool, %{}) do
          {:ok, result} -> to_string(result)
          _ -> ""
        end
      end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
    end
  end
```

**Step 5: Run reflect tests**

```bash
tmux-cli send 'mix test test/ex_cortex/step_runner_test.exs 2>&1 | tail -10' --pane=main:1.3
```

**Step 6: Run full suite**

```bash
tmux-cli send 'mix test 2>&1 | tail -5' --pane=main:1.3
```

**Step 7: Commit**

```bash
tmux-cli send 'git add lib/ex_cortex/quests/step.ex lib/ex_cortex/step_runner.ex test/ex_cortex/step_runner_test.exs && git commit -m "feat: add reflect mode to StepRunner — tool-assisted context gathering with retry"' --pane=main:1.3
```

---

## Task 6: Format check + full suite

**Step 1: Format**

```bash
tmux-cli send 'mix format' --pane=main:1.3
```

**Step 2: Full test suite**

```bash
tmux-cli send 'mix test 2>&1 | tail -10' --pane=main:1.3
```

Expected: all pass, 0 failures

**Step 3: Commit any format fixes**

```bash
tmux-cli send 'git add -p && git commit -m "style: mix format"' --pane=main:1.3
```

---

## Implementation Order Summary

1. Tool registry using `ReqLLM.Tool` (foundation — everything else depends on it)
2. Claude agent loop via `ReqLLM.generate_text` + `Context.execute_and_append_tools`
3. Wire tools into StepRunner member calls
4. Escalate mode (rank ladder)
5. Reflect mode (context gathering + retry using `ReqLLM.Tool.execute/2`)
6. Format + full suite

## Notes

- **No custom Executor needed** — `ReqLLM.Context.execute_and_append_tools/3` handles parallel tool execution and result threading for the Claude loop. `ReqLLM.Tool.execute/2` handles single-tool calls in reflect mode.
- **Ollama tool calling** is intentionally deferred — it requires models that support function calling (llama3.1+, mistral-nemo etc.). The architecture supports it: pass the same `ReqLLM.Tool` list to Ollama's path once model support is confirmed.
- **YOLO gate**: `FetchUrl` is implemented and listed only in `@yolo_entries`. The `run_code` tool is left for later — sandboxing Elixir execution needs careful thought.
- **Step schema migration**: Adding fields to the Step schema requires a migration if deploying to a running system. For dev, `mix ecto.reset` is sufficient.
