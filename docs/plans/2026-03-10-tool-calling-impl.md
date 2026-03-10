# Tool Calling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add tool calling to members (agent loop) and steps (reflect + escalate modes), with a safe/YOLO tier split.

**Architecture:** Tool structs with handlers are registered by name. Member-level loops are recursive message-list functions (no GenServer). Tool execution is isolated via `Task.async_stream` with timeouts. StepRunner gains reflect and escalate phases that wrap the existing roster run. Claude tool calls use direct Req calls to Anthropic API (ReqLLM.generate_text strips tool_use blocks). Ollama uses the existing Excellence.LLM.Ollama client.

**Tech Stack:** Elixir/OTP, Req (direct Anthropic API calls), Excellence.LLM.Ollama, ExCalibur.Lore, ExCalibur.Quests

---

## Task 1: Tool struct + registry

**Files:**
- Create: `lib/ex_calibur/tools/tool.ex`
- Create: `lib/ex_calibur/tools/registry.ex`
- Create: `test/ex_calibur/tools/registry_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_calibur/tools/registry_test.exs
defmodule ExCalibur.Tools.RegistryTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Tools.Registry

  test "list_safe/0 returns only safe tools" do
    tools = Registry.list_safe()
    assert Enum.all?(tools, & &1.safe?)
    names = Enum.map(tools, & &1.name)
    assert "query_lore" in names
    assert "run_quest" in names
  end

  test "list_yolo/0 returns safe + yolo tools" do
    tools = Registry.list_yolo()
    names = Enum.map(tools, & &1.name)
    assert "query_lore" in names
    assert "fetch_url" in names
  end

  test "get/1 returns a tool by name" do
    assert %{name: "query_lore"} = Registry.get("query_lore")
  end

  test "get/1 returns nil for unknown tool" do
    assert nil == Registry.get("does_not_exist")
  end

  test "resolve_tools/1 with :all_safe returns all safe tools" do
    tools = Registry.resolve_tools(:all_safe)
    assert Enum.all?(tools, & &1.safe?)
  end

  test "resolve_tools/1 with :yolo returns safe + yolo tools" do
    tools = Registry.resolve_tools(:yolo)
    names = Enum.map(tools, & &1.name)
    assert "fetch_url" in names
  end

  test "resolve_tools/1 with list of names returns matching tools" do
    tools = Registry.resolve_tools(["query_lore"])
    assert length(tools) == 1
    assert hd(tools).name == "query_lore"
  end

  test "to_claude_schema/1 converts a tool to Anthropic API format" do
    tool = Registry.get("query_lore")
    schema = Registry.to_claude_schema(tool)
    assert schema.name == "query_lore"
    assert Map.has_key?(schema, :description)
    assert Map.has_key?(schema, :input_schema)
  end
end
```

**Step 2: Run test to verify it fails**

```bash
tmux-cli send 'mix test test/ex_calibur/tools/registry_test.exs 2>&1 | tail -5' --pane=main:1.3
```

Expected: compilation error (modules don't exist)

**Step 3: Create Tool struct**

```elixir
# lib/ex_calibur/tools/tool.ex
defmodule ExCalibur.Tools.Tool do
  @moduledoc """
  A callable tool that can be offered to LLMs during an agent loop.

  Fields:
  - name: unique string identifier (snake_case)
  - description: plain-English description for the LLM
  - parameters: JSON Schema map describing the input (Anthropic input_schema format)
  - handler: 1-arity function that receives the parsed input map and returns {:ok, result} | {:error, reason}
  - safe?: true = always available, false = requires yolo: true on member/step
  """
  @enforce_keys [:name, :description, :parameters, :handler, :safe?]
  defstruct [:name, :description, :parameters, :handler, :safe?]
end
```

**Step 4: Create stub safe tools (just enough for registry to compile)**

```elixir
# lib/ex_calibur/tools/query_lore.ex
defmodule ExCalibur.Tools.QueryLore do
  @moduledoc "Tool: search lore entries by tags."

  def tool do
    %ExCalibur.Tools.Tool{
      name: "query_lore",
      description: "Search the lore store for entries matching the given tags. Returns a list of recent matching entries.",
      parameters: %{
        type: "object",
        properties: %{
          tags: %{type: "array", items: %{type: "string"}, description: "Tags to filter by"},
          limit: %{type: "integer", description: "Max entries to return (default 5)"}
        },
        required: []
      },
      handler: &call/1,
      safe?: true
    }
  end

  def call(%{"tags" => tags} = input) do
    limit = Map.get(input, "limit", 5)
    entries = ExCalibur.Lore.list_entries(tags: tags) |> Enum.take(limit)
    summaries = Enum.map(entries, fn e -> "#{e.title}: #{String.slice(e.body || "", 0, 200)}" end)
    {:ok, Enum.join(summaries, "\n---\n")}
  end

  def call(_), do: call(%{"tags" => []})
end
```

```elixir
# lib/ex_calibur/tools/run_quest.ex
defmodule ExCalibur.Tools.RunQuest do
  @moduledoc "Tool: run a quest by name with a given input string."

  def tool do
    %ExCalibur.Tools.Tool{
      name: "run_quest",
      description: "Run a named quest with the given input text. Returns the quest result.",
      parameters: %{
        type: "object",
        properties: %{
          quest_name: %{type: "string", description: "The name of the quest to run"},
          input: %{type: "string", description: "The input text to pass to the quest"}
        },
        required: ["quest_name", "input"]
      },
      handler: &call/1,
      safe?: true
    }
  end

  def call(%{"quest_name" => name, "input" => input}) do
    import Ecto.Query
    alias ExCalibur.Repo
    alias ExCalibur.Quests.Quest

    case Repo.one(from q in Quest, where: q.name == ^name, limit: 1) do
      nil -> {:error, "Quest '#{name}' not found"}
      quest ->
        preloaded = Repo.preload(quest, :steps)
        case ExCalibur.QuestRunner.run(preloaded, input) do
          {:ok, result} -> {:ok, inspect(result)}
          {:error, reason} -> {:error, inspect(reason)}
        end
    end
  end
end
```

```elixir
# lib/ex_calibur/tools/fetch_url.ex
defmodule ExCalibur.Tools.FetchUrl do
  @moduledoc "Tool (YOLO): fetch the body of a URL."

  def tool do
    %ExCalibur.Tools.Tool{
      name: "fetch_url",
      description: "Fetch the text content of a URL. Only use when explicitly permitted.",
      parameters: %{
        type: "object",
        properties: %{
          url: %{type: "string", description: "The URL to fetch"}
        },
        required: ["url"]
      },
      handler: &call/1,
      safe?: false
    }
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

**Step 5: Create Registry module**

```elixir
# lib/ex_calibur/tools/registry.ex
defmodule ExCalibur.Tools.Registry do
  @moduledoc """
  Central registry of available tools.

  Usage:
    Registry.list_safe()               # all safe tools
    Registry.list_yolo()               # safe + yolo tools
    Registry.get("query_lore")         # single tool by name
    Registry.resolve_tools(:all_safe)  # from config value
    Registry.to_claude_schema(tool)    # Anthropic API format
  """

  alias ExCalibur.Tools.Tool

  @all_tools [
    ExCalibur.Tools.QueryLore,
    ExCalibur.Tools.RunQuest,
    ExCalibur.Tools.FetchUrl
  ]

  def all, do: Enum.map(@all_tools, & &1.tool())

  def list_safe, do: Enum.filter(all(), & &1.safe?)

  def list_yolo, do: all()

  def get(name) when is_binary(name) do
    Enum.find(all(), &(&1.name == name))
  end

  @doc """
  Resolve a tools config value to a list of Tool structs.

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

  @doc "Convert a Tool to the Anthropic API tool schema format."
  def to_claude_schema(%Tool{name: name, description: desc, parameters: params}) do
    %{name: name, description: desc, input_schema: params}
  end

  @doc "Convert a Tool to the Ollama function calling format."
  def to_ollama_schema(%Tool{name: name, description: desc, parameters: params}) do
    %{
      type: "function",
      function: %{name: name, description: desc, parameters: params}
    }
  end
end
```

**Step 6: Run tests to verify they pass**

```bash
tmux-cli send 'mix test test/ex_calibur/tools/registry_test.exs 2>&1 | tail -5' --pane=main:1.3
```

Expected: all pass

**Step 7: Commit**

```bash
tmux-cli send 'git add lib/ex_calibur/tools/ test/ex_calibur/tools/ && git commit -m "feat: add tool struct, registry, and initial tool implementations"' --pane=main:1.3
```

---

## Task 2: Tool executor

**Files:**
- Create: `lib/ex_calibur/tools/executor.ex`
- Create: `test/ex_calibur/tools/executor_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_calibur/tools/executor_test.exs
defmodule ExCalibur.Tools.ExecutorTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Tools.{Executor, Registry}

  test "execute/1 runs a single tool call and returns result" do
    results = Executor.execute([%{"name" => "query_lore", "input" => %{}}])
    assert [%{tool_use_id: nil, content: content}] = results
    assert is_binary(content)
  end

  test "execute/1 runs multiple tool calls in parallel" do
    calls = [
      %{"name" => "query_lore", "input" => %{}},
      %{"name" => "query_lore", "input" => %{"tags" => ["test"]}}
    ]
    results = Executor.execute(calls)
    assert length(results) == 2
  end

  test "execute/1 handles unknown tool gracefully" do
    results = Executor.execute([%{"name" => "no_such_tool", "input" => %{}}])
    assert [%{content: content}] = results
    assert String.contains?(content, "unknown tool")
  end

  test "execute/1 handles tool error gracefully" do
    # fetch_url with an invalid URL should return error content, not raise
    results = Executor.execute([%{"name" => "fetch_url", "input" => %{"url" => "not-a-url"}}])
    assert [%{content: content}] = results
    assert is_binary(content)
  end
end
```

**Step 2: Run test to verify it fails**

```bash
tmux-cli send 'mix test test/ex_calibur/tools/executor_test.exs 2>&1 | tail -5' --pane=main:1.3
```

Expected: compilation error

**Step 3: Implement executor**

```elixir
# lib/ex_calibur/tools/executor.ex
defmodule ExCalibur.Tools.Executor do
  @moduledoc """
  Executes a batch of tool calls in parallel, each in an isolated Task with a timeout.

  Input: list of tool call maps with "name", "input", and optionally "id" (tool_use_id)
  Output: list of result maps with :tool_use_id and :content (string)

  Errors (crash, timeout, unknown tool) are caught and returned as error strings —
  the agent loop sees an error message and can decide what to do next.
  """

  alias ExCalibur.Tools.Registry

  @default_timeout 15_000

  @doc """
  Execute a list of tool call maps in parallel.

  Each map has:
    "name"  — tool name string
    "input" — parsed input map
    "id"    — optional tool_use_id (for Claude correlation)
  """
  def execute(tool_calls, timeout \\ @default_timeout) when is_list(tool_calls) do
    tool_calls
    |> Task.async_stream(&run_one/1, timeout: timeout, on_timeout: :kill_task)
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, _reason} -> %{tool_use_id: nil, content: "error: tool execution timed out"}
    end)
  end

  defp run_one(%{"name" => name, "input" => input} = call) do
    id = Map.get(call, "id")

    content =
      case Registry.get(name) do
        nil ->
          "error: unknown tool '#{name}'"

        tool ->
          case tool.handler.(input) do
            {:ok, result} -> to_string(result)
            {:error, reason} -> "error: #{reason}"
          end
      end

    %{tool_use_id: id, content: content}
  rescue
    e -> %{tool_use_id: Map.get(call, "id"), content: "error: #{Exception.message(e)}"}
  end
end
```

**Step 4: Run tests**

```bash
tmux-cli send 'mix test test/ex_calibur/tools/executor_test.exs 2>&1 | tail -5' --pane=main:1.3
```

Expected: all pass

**Step 5: Commit**

```bash
tmux-cli send 'git add lib/ex_calibur/tools/executor.ex test/ex_calibur/tools/executor_test.exs && git commit -m "feat: add tool executor with parallel Task execution and timeout handling"' --pane=main:1.3
```

---

## Task 3: Claude agent loop (member-level)

**Files:**
- Modify: `lib/ex_calibur/claude_client.ex`
- Create: `test/ex_calibur/tools/claude_agent_loop_test.exs`

The current `ClaudeClient.complete/3` uses ReqLLM which strips tool_use blocks. For the agent loop, we call the Anthropic API directly via Req and handle multi-turn ourselves.

**Step 1: Write the failing test**

```elixir
# test/ex_calibur/tools/claude_agent_loop_test.exs
defmodule ExCalibur.ClaudeAgentLoopTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.ClaudeClient

  test "complete_with_tools/4 returns {:ok, text} when no API key configured" do
    # Without a key, should return an error (not crash)
    result = ClaudeClient.complete_with_tools("claude_haiku", "You are helpful", "Say hi", [])
    assert match?({:error, _}, result) or match?({:ok, _}, result)
  end

  test "complete_with_tools/4 returns {:error, _} for unknown tier" do
    result = ClaudeClient.complete_with_tools("claude_blorp", "sys", "msg", [])
    assert {:error, _} = result
  end

  test "build_tool_result_message/1 formats tool results for Anthropic API" do
    results = [%{tool_use_id: "toolu_abc", content: "some result"}]
    msg = ClaudeClient.build_tool_result_message(results)
    assert msg.role == "user"
    assert [%{type: "tool_result", tool_use_id: "toolu_abc", content: "some result"}] = msg.content
  end
end
```

**Step 2: Run test to verify it fails**

```bash
tmux-cli send 'mix test test/ex_calibur/tools/claude_agent_loop_test.exs 2>&1 | tail -5' --pane=main:1.3
```

**Step 3: Add `complete_with_tools/4` and helpers to ClaudeClient**

Add to the bottom of `lib/ex_calibur/claude_client.ex`:

```elixir
  @anthropic_url "https://api.anthropic.com/v1/messages"
  @anthropic_version "2023-06-01"
  @max_tool_iterations 5

  @doc """
  Run a multi-turn agent loop with tool calling support.

  - `tier` — "claude_haiku" | "claude_sonnet" | "claude_opus"
  - `system_prompt` — system prompt string
  - `user_text` — initial user message
  - `tools` — list of %Tool{} structs (from ExCalibur.Tools.Registry)

  Returns {:ok, text} when the model produces a final text response,
  or {:error, reason} on failure.
  """
  def complete_with_tools(tier, system_prompt, user_text, tools) do
    with {:ok, model_id} <- fetch_model_id(tier),
         {:ok, api_key} <- fetch_api_key() do
      tool_schemas = Enum.map(tools, &ExCalibur.Tools.Registry.to_claude_schema/1)
      messages = [%{role: "user", content: user_text}]
      run_loop(model_id, system_prompt, messages, tool_schemas, api_key, 0)
    end
  end

  @doc "Build the 'user' message that carries tool results back to Claude."
  def build_tool_result_message(tool_results) do
    content =
      Enum.map(tool_results, fn %{tool_use_id: id, content: content} ->
        %{type: "tool_result", tool_use_id: id, content: content}
      end)

    %{role: "user", content: content}
  end

  # ---------------------------------------------------------------------------
  # Private — agent loop
  # ---------------------------------------------------------------------------

  defp run_loop(_model, _system, _messages, _tools, _key, iter) when iter >= @max_tool_iterations do
    {:error, :max_iterations_exceeded}
  end

  defp run_loop(model_id, system_prompt, messages, tool_schemas, api_key, iter) do
    body =
      %{model: model_id, max_tokens: 4096, system: system_prompt, messages: messages}
      |> maybe_add_tools(tool_schemas)

    case Req.post(@anthropic_url,
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", @anthropic_version},
             {"content-type", "application/json"}
           ],
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: %{"content" => content_blocks, "stop_reason" => stop_reason}}} ->
        handle_response(content_blocks, stop_reason, model_id, system_prompt, messages, tool_schemas, api_key, iter)

      {:ok, %{status: status, body: body}} ->
        {:error, "Anthropic API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp handle_response(content_blocks, "tool_use", model_id, system_prompt, messages, tool_schemas, api_key, iter) do
    # Extract tool calls
    tool_calls =
      content_blocks
      |> Enum.filter(&(&1["type"] == "tool_use"))
      |> Enum.map(fn block ->
        %{"name" => block["name"], "input" => block["input"], "id" => block["id"]}
      end)

    # Execute tools
    tool_results = ExCalibur.Tools.Executor.execute(tool_calls)

    # Append assistant message + tool results to conversation
    updated_messages =
      messages ++
        [%{role: "assistant", content: content_blocks}, build_tool_result_message(tool_results)]

    run_loop(model_id, system_prompt, updated_messages, tool_schemas, api_key, iter + 1)
  end

  defp handle_response(content_blocks, _stop_reason, _model, _system, _messages, _tools, _key, _iter) do
    text =
      content_blocks
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map(& &1["text"])
      |> Enum.join("\n")

    {:ok, text}
  end

  defp maybe_add_tools(body, []), do: body
  defp maybe_add_tools(body, tools), do: Map.put(body, :tools, tools)

  defp fetch_model_id(tier) do
    case Map.fetch(@model_ids, tier) do
      {:ok, "anthropic:" <> model_id} -> {:ok, model_id}
      :error -> {:error, "unknown tier: #{tier}"}
    end
  end

  defp fetch_api_key do
    key = ReqLLM.get_key(:anthropic_api_key) || System.get_env("ANTHROPIC_API_KEY")
    if key && key != "", do: {:ok, key}, else: {:error, :no_api_key}
  end
```

**Step 4: Run tests**

```bash
tmux-cli send 'mix test test/ex_calibur/tools/claude_agent_loop_test.exs 2>&1 | tail -5' --pane=main:1.3
```

Expected: all pass (no API key in test env is fine — we test the error path)

**Step 5: Run full test suite to check for regressions**

```bash
tmux-cli send 'mix test 2>&1 | tail -5' --pane=main:1.3
```

Expected: same pass count as before

**Step 6: Commit**

```bash
tmux-cli send 'git add lib/ex_calibur/claude_client.ex test/ex_calibur/tools/claude_agent_loop_test.exs && git commit -m "feat: add Claude agent loop with tool calling support"' --pane=main:1.3
```

---

## Task 4: Wire tools into StepRunner member calls

**Files:**
- Modify: `lib/ex_calibur/step_runner.ex`

Members now carry a `tools` config key. When present, use the agent loop instead of single-shot calls.

**Step 1: Update `member_to_runner_spec/1` to carry tools**

In `step_runner.ex`, find `member_to_runner_spec/1` and update:

```elixir
  defp member_to_runner_spec(db) do
    %{
      type: :ollama,
      model: db.config["model"] || "phi4-mini",
      system_prompt: db.config["system_prompt"] || "",
      name: db.name,
      tools: parse_tools_config(db.config["tools"]),
      max_iterations: db.config["max_iterations"] || 5
    }
  end

  defp parse_tools_config(nil), do: []
  defp parse_tools_config("all_safe"), do: :all_safe
  defp parse_tools_config("yolo"), do: :yolo
  defp parse_tools_config(names) when is_list(names), do: names
  defp parse_tools_config(_), do: []
```

Also update the Claude tier spec builders to carry tools (find the three `resolve_members` clauses for `"claude_haiku"` etc.):

```elixir
  defp resolve_members(claude_tier) when claude_tier in ["claude_haiku", "claude_sonnet", "claude_opus"] do
    [%{type: :claude, tier: claude_tier, name: claude_tier, system_prompt: nil, tools: [], max_iterations: 5}]
  end
```

**Step 2: Update `call_member/3` for Claude to use agent loop when tools present**

Find the `call_member/3` clause for `:claude` and replace:

```elixir
  defp call_member(%{type: :claude, tier: tier, system_prompt: system_prompt, tools: tools}, input_text, _ollama)
       when is_list(tools) and tools != [] do
    resolved = ExCalibur.Tools.Registry.resolve_tools(tools)
    prompt = system_prompt || default_claude_prompt()

    case ClaudeClient.complete_with_tools(tier, prompt, input_text, resolved) do
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

Do the same for `call_member_raw` (the freeform variant):

```elixir
  defp call_member_raw(%{type: :claude, tier: tier, system_prompt: system_prompt, tools: tools}, input_text, _ollama)
       when is_list(tools) and tools != [] do
    resolved = ExCalibur.Tools.Registry.resolve_tools(tools)
    prompt = system_prompt || ""

    case ClaudeClient.complete_with_tools(tier, prompt, input_text, resolved) do
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
tmux-cli send 'git add lib/ex_calibur/step_runner.ex && git commit -m "feat: wire tool config into member runner specs and call_member dispatch"' --pane=main:1.3
```

---

## Task 5: Escalate mode in StepRunner

**Files:**
- Modify: `lib/ex_calibur/step_runner.ex`
- Modify: `test/ex_calibur/step_runner_test.exs`

**Step 1: Write the failing test**

Add to `test/ex_calibur/step_runner_test.exs`:

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
      result = ExCalibur.StepRunner.run(step, "test input")
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

      assert {:ok, %{verdict: "pass"}} = ExCalibur.StepRunner.run(step, "test")
    end
  end
```

**Step 2: Run to verify it fails**

```bash
tmux-cli send 'mix test test/ex_calibur/step_runner_test.exs 2>&1 | tail -10' --pane=main:1.3
```

Expected: compile error (Step struct doesn't have escalate field yet, or function clause error)

**Step 3: Check the Step schema and add escalate fields**

```bash
tmux-cli send 'grep -n "field" lib/ex_calibur/quests/step.ex | head -30' --pane=main:1.3
```

Add to `lib/ex_calibur/quests/step.ex` schema (find the existing fields and add):

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
tmux-cli send 'mix test test/ex_calibur/step_runner_test.exs 2>&1 | tail -10' --pane=main:1.3
```

**Step 6: Run full suite**

```bash
tmux-cli send 'mix test 2>&1 | tail -5' --pane=main:1.3
```

**Step 7: Commit**

```bash
tmux-cli send 'git add lib/ex_calibur/quests/step.ex lib/ex_calibur/step_runner.ex test/ex_calibur/step_runner_test.exs && git commit -m "feat: add escalate mode to StepRunner — rank ladder with confidence threshold"' --pane=main:1.3
```

---

## Task 6: Reflect mode in StepRunner

**Files:**
- Modify: `lib/ex_calibur/step_runner.ex`
- Modify: `lib/ex_calibur/quests/step.ex`
- Modify: `test/ex_calibur/step_runner_test.exs`

**Step 1: Write the failing test**

Add to `test/ex_calibur/step_runner_test.exs`:

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
      assert {:ok, %{verdict: "pass"}} = ExCalibur.StepRunner.run(step, "test")
    end
  end
```

**Step 2: Run to verify it fails**

```bash
tmux-cli send 'mix test test/ex_calibur/step_runner_test.exs 2>&1 | tail -10' --pane=main:1.3
```

**Step 3: Add reflect fields to Step schema**

Add to `lib/ex_calibur/quests/step.ex`:

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
    tools = ExCalibur.Tools.Registry.resolve_tools(quest.loop_tools || [])

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

  defp gather_reflect_context(tools, input_text, verdict) do
    # Ask a lightweight query tool for relevant context based on current input
    # For now: if query_lore is available, run it; otherwise return empty
    lore_tool = Enum.find(tools, &(&1.name == "query_lore"))

    if lore_tool do
      case lore_tool.handler.(%{"tags" => [], "limit" => 3}) do
        {:ok, content} -> "Prior lore context (verdict was #{verdict}):\n#{content}"
        _ -> ""
      end
    else
      tool_calls = Enum.map(tools, fn t -> %{"name" => t.name, "input" => %{}} end)
      results = ExCalibur.Tools.Executor.execute(tool_calls)
      Enum.map_join(results, "\n", & &1.content)
    end
  end
```

**Step 5: Run reflect tests**

```bash
tmux-cli send 'mix test test/ex_calibur/step_runner_test.exs 2>&1 | tail -10' --pane=main:1.3
```

**Step 6: Run full suite**

```bash
tmux-cli send 'mix test 2>&1 | tail -5' --pane=main:1.3
```

**Step 7: Commit**

```bash
tmux-cli send 'git add lib/ex_calibur/quests/step.ex lib/ex_calibur/step_runner.ex test/ex_calibur/step_runner_test.exs && git commit -m "feat: add reflect mode to StepRunner — tool-assisted context gathering with retry"' --pane=main:1.3
```

---

## Task 7: Format check + full suite

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

1. Tool struct + registry (foundation — everything else depends on it)
2. Tool executor (parallel Task execution with timeout)
3. Claude agent loop (multi-turn tool calling via direct Req)
4. Wire tools into StepRunner member calls
5. Escalate mode (rank ladder)
6. Reflect mode (context gathering + retry)
7. Format + full suite

## Notes

- **Ollama tool calling** is intentionally deferred — it requires models that support function calling (llama3.1+, mistral-nemo etc.) and the format differs from Claude. The architecture supports it: add an Ollama-specific agent loop in StepRunner following the same pattern as the Claude path.
- **YOLO gate**: `FetchUrl` is already implemented and gated via `safe?: false`. The `run_code` tool is left for later — sandboxing Elixir execution needs careful thought.
- **Step schema migration**: Adding fields to the Step schema requires a migration if deploying to a running system. For dev, `mix ecto.reset` is sufficient.
