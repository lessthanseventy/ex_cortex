# Self-Improvement Guardrails Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add five structural guardrails to the self-improvement quest pipeline: verdict gates, dangerous tool interception, iteration circuit breaker, rollback on failure, and Styler guard.

**Architecture:** Verdict gates live in quest_runner.ex's step iteration loop. Dangerous tool interception hooks into the Ollama/Claude agent loops via an opts-based mode flag. Circuit breaker tracks consecutive empty results per tool in the agent loop. Rollback wraps step execution in step_runner.ex with git stash/checkout. Styler guard auto-formats before git_commit.

**Tech Stack:** Elixir, Ecto (Step schema), ExCalibur.LLM (Ollama/Claude providers), Git (System.cmd)

---

### Task 0: Add `dangerous_tool_mode` and `max_tool_iterations` to Step Schema

**Files:**
- Modify: `lib/ex_calibur/quests/step.ex`
- Create: `priv/repo/migrations/*_add_step_guardrail_fields.exs`

**Step 1: Create migration**

```elixir
# priv/repo/migrations/TIMESTAMP_add_step_guardrail_fields.exs
defmodule ExCalibur.Repo.Migrations.AddStepGuardrailFields do
  use Ecto.Migration

  def change do
    alter table(:excellence_steps) do
      add :dangerous_tool_mode, :string, default: "execute"
      add :max_tool_iterations, :integer, default: 15
    end
  end
end
```

**Step 2: Add fields to Step schema**

In `lib/ex_calibur/quests/step.ex`, add after `field :guild_name, :string`:

```elixir
field :dangerous_tool_mode, :string, default: "execute"
field :max_tool_iterations, :integer, default: 15
```

Add `:dangerous_tool_mode` and `:max_tool_iterations` to the `@optional` list.

Add validation in `changeset/2`:

```elixir
|> validate_inclusion(:dangerous_tool_mode, ~w(execute intercept dry_run))
```

**Step 3: Run migration**

Run: `mix ecto.migrate`
Expected: migration succeeds

**Step 4: Run tests**

Run: `mix test test/ex_calibur/quests/`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_calibur/quests/step.ex priv/repo/migrations/*_add_step_guardrail_fields.exs
git commit -m "feat: add dangerous_tool_mode and max_tool_iterations fields to Step schema"
```

---

### Task 1: Iteration Circuit Breaker in Ollama Agent Loop

**Files:**
- Modify: `lib/ex_calibur/llm/ollama.ex:86-153`
- Create: `test/ex_calibur/llm/circuit_breaker_test.exs`

**Step 1: Write failing test**

```elixir
# test/ex_calibur/llm/circuit_breaker_test.exs
defmodule ExCalibur.LLM.CircuitBreakerTest do
  use ExUnit.Case, async: true

  alias ExCalibur.LLM.Ollama

  describe "empty_result?/1" do
    test "detects empty string" do
      assert Ollama.empty_result?("")
    end

    test "detects empty list string" do
      assert Ollama.empty_result?("[]\n")
    end

    test "detects error string" do
      assert Ollama.empty_result?("Error: something failed")
    end

    test "rejects non-empty content" do
      refute Ollama.empty_result?("some real content here")
    end
  end

  describe "check_circuit_breaker/3" do
    test "returns :ok for first empty result" do
      assert {:ok, %{"my_tool" => 1}} = Ollama.check_circuit_breaker("my_tool", "", %{})
    end

    test "returns :ok for second empty result" do
      assert {:ok, %{"my_tool" => 2}} = Ollama.check_circuit_breaker("my_tool", "", %{"my_tool" => 1})
    end

    test "returns :tripped on third empty result" do
      assert {:tripped, _} = Ollama.check_circuit_breaker("my_tool", "", %{"my_tool" => 2})
    end

    test "resets counter on non-empty result" do
      assert {:ok, %{"my_tool" => 0}} = Ollama.check_circuit_breaker("my_tool", "real data", %{"my_tool" => 2})
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_calibur/llm/circuit_breaker_test.exs`
Expected: FAIL — functions not defined

**Step 3: Add circuit breaker functions to Ollama module**

Add these public functions to `lib/ex_calibur/llm/ollama.ex` (after `fallback_models_for/2`):

```elixir
@empty_threshold 3

def empty_result?(output) when is_binary(output) do
  trimmed = String.trim(output)
  trimmed == "" or trimmed == "[]" or trimmed == "[]\n" or String.starts_with?(trimmed, "Error:")
end

def empty_result?(_), do: true

def check_circuit_breaker(tool_name, output, breaker_state) do
  if empty_result?(output) do
    count = Map.get(breaker_state, tool_name, 0) + 1

    if count >= @empty_threshold do
      {:tripped, Map.put(breaker_state, tool_name, count)}
    else
      {:ok, Map.put(breaker_state, tool_name, count)}
    end
  else
    {:ok, Map.put(breaker_state, tool_name, 0)}
  end
end
```

**Step 4: Wire circuit breaker into `execute_tool_calls/2`**

Change `execute_tool_calls/2` signature to `execute_tool_calls/3` accepting breaker state. In the reduce, after getting the output, call `check_circuit_breaker/3`. If `:tripped`, replace the output with a skip message and don't execute the tool.

Update `run_tool_loop/7` to `run_tool_loop/8` passing breaker state through, initializing as `%{}`.

In `execute_tool_calls/3`:

```elixir
defp execute_tool_calls(calls, tools, breaker_state) do
  Enum.reduce(calls, {[], [], breaker_state}, fn call, {msgs, log, bs} ->
    name = get_in(call, ["function", "name"])
    args_raw = get_in(call, ["function", "arguments"])

    args =
      case args_raw do
        s when is_binary(s) -> Jason.decode!(s)
        m when is_map(m) -> m
        _ -> %{}
      end

    # Check if this tool is circuit-broken
    prior_count = Map.get(bs, name, 0)

    {output, log_entry, new_bs} =
      if prior_count >= @empty_threshold do
        out = "Tool #{name} returned empty results #{prior_count} times. Skipping — proceed with available information."
        Logger.debug("[Ollama] circuit breaker: skipping #{name}")
        {out, %{tool: name, input: args, output: out}, bs}
      else
        tool = Enum.find(tools, &(&1.name == name))

        {out, entry} =
          if tool do
            case ReqLLM.Tool.execute(tool, args) do
              {:ok, v} ->
                o = to_string(v)
                Logger.debug("[Ollama] tool #{name} → #{String.slice(o, 0, 120)}")
                {o, %{tool: name, input: args, output: o}}

              {:error, e} ->
                o = "Error: #{inspect(e)}"
                {o, %{tool: name, input: args, output: o}}
            end
          else
            o = "Tool #{name} not found"
            {o, %{tool: name, input: args, output: o}}
          end

        {:ok, updated_bs} = check_circuit_breaker(name, out, bs)
        {out, entry, updated_bs}
      end

    tool_msg = %{role: "tool", content: output}
    {msgs ++ [tool_msg], log ++ [log_entry], new_bs}
  end)
end
```

Update `run_tool_loop` to pass and thread `breaker_state`:

```elixir
# Change signature: add breaker_state as 8th param
defp run_tool_loop(ollama, models, messages, tools, ollama_tools, iter, tool_log, breaker_state)
```

In `complete_with_tools/5`, initialize: `run_tool_loop(ollama, models, messages, tools, ollama_tools, 0, [], %{})`

In the `{:ok, %{"tool_calls" => calls}}` branch:
```elixir
{tool_msgs, new_entries, new_bs} = execute_tool_calls(calls, tools, breaker_state)
run_tool_loop(ollama, models, new_messages, tools, ollama_tools, iter + 1, tool_log ++ new_entries, new_bs)
```

**Step 5: Support per-step max_tool_iterations via opts**

Change `@max_tool_iterations 15` to read from opts:

In `complete_with_tools/5`:
```elixir
max_iter = Keyword.get(opts, :max_tool_iterations, 15)
```

Pass `max_iter` into `run_tool_loop` and use it instead of `@max_tool_iterations`.

**Step 6: Run tests**

Run: `mix test test/ex_calibur/llm/circuit_breaker_test.exs`
Expected: PASS

Run: `mix test`
Expected: PASS (no regressions)

**Step 7: Commit**

```bash
git add lib/ex_calibur/llm/ollama.ex test/ex_calibur/llm/circuit_breaker_test.exs
git commit -m "feat: add iteration circuit breaker to Ollama agent loop"
```

---

### Task 2: Iteration Circuit Breaker in Claude Agent Loop

**Files:**
- Modify: `lib/ex_calibur/llm/claude.ex:80-120`

**Step 1: Add circuit breaker to Claude's `execute_tools_with_log/3`**

Same pattern as Ollama. Change `execute_tools_with_log/3` to `execute_tools_with_log/4` accepting breaker state. Reuse `ExCalibur.LLM.Ollama.empty_result?/1` and `check_circuit_breaker/3` (they're public).

In `run_agent_loop`, thread breaker state and read `max_tool_iterations` from an opts parameter.

**Step 2: Run tests**

Run: `mix test`
Expected: PASS

**Step 3: Commit**

```bash
git add lib/ex_calibur/llm/claude.ex
git commit -m "feat: add iteration circuit breaker to Claude agent loop"
```

---

### Task 3: Dangerous Tool Interception

**Files:**
- Modify: `lib/ex_calibur/llm/ollama.ex` (execute_tool_calls)
- Modify: `lib/ex_calibur/llm/claude.ex` (execute_tools_with_log)
- Modify: `lib/ex_calibur/step_runner.ex` (pass opts through)
- Modify: `lib/ex_calibur/llm.ex` (if it exists — add opts to behaviour)
- Create: `test/ex_calibur/step_runner/dangerous_tool_interception_test.exs`

**Step 1: Write failing test**

```elixir
# test/ex_calibur/step_runner/dangerous_tool_interception_test.exs
defmodule ExCalibur.StepRunner.DangerousToolInterceptionTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.StepRunner

  describe "dangerous?/1" do
    test "close_issue is dangerous" do
      assert StepRunner.dangerous?("close_issue")
    end

    test "read_file is not dangerous" do
      refute StepRunner.dangerous?("read_file")
    end
  end
end
```

**Step 2: Run test — should already pass (dangerous?/1 exists)**

Run: `mix test test/ex_calibur/step_runner/dangerous_tool_interception_test.exs`
Expected: PASS

**Step 3: Add `dangerous_tool_mode` to opts flow**

In `lib/ex_calibur/step_runner.ex`, modify `call_member/2` and `call_member_raw/2` to accept an opts keyword list and pass it through to `ExCalibur.LLM.complete_with_tools/5`:

```elixir
defp call_member(member, input_text, opts \\ []) do
  # ... existing code ...
  result =
    if tools == [] do
      ExCalibur.LLM.complete(provider, model, prompt, input_text)
    else
      ExCalibur.LLM.complete_with_tools(provider, model, prompt, input_text, tools, opts)
    end
  # ...
end
```

In the `run/2` functions that call `call_member`, pass the step's `dangerous_tool_mode` and `max_tool_iterations`:

```elixir
opts = [
  dangerous_tool_mode: quest.dangerous_tool_mode || "execute",
  max_tool_iterations: quest.max_tool_iterations || 15
]
```

**Step 4: Hook interception into Ollama's `execute_tool_calls`**

In the tool execution branch, before `ReqLLM.Tool.execute(tool, args)`, check if the tool is dangerous:

```elixir
dangerous_mode = Keyword.get(opts, :dangerous_tool_mode, "execute")

{out, entry} =
  if tool do
    if StepRunner.dangerous?(name) and dangerous_mode != "execute" do
      handle_dangerous_tool(name, args, dangerous_mode, opts)
    else
      # existing execute logic
    end
  else
    # existing "not found" logic
  end
```

Add helper:

```elixir
defp handle_dangerous_tool(name, args, "intercept", opts) do
  quest_id = Keyword.get(opts, :quest_id)

  case StepRunner.intercept_dangerous_tool(name, args, quest_id) do
    {:ok, proposal} ->
      out = "Tool call queued for human approval. Proposal ID: #{proposal.id}. Continue without this result."
      {out, %{tool: name, input: args, output: out}}

    _ ->
      out = "Failed to create proposal for #{name}. Skipping."
      {out, %{tool: name, input: args, output: out}}
  end
end

defp handle_dangerous_tool(name, args, "dry_run", _opts) do
  out = "DRY RUN: Would have called #{name} with #{Jason.encode!(args)}. No action taken."
  {out, %{tool: name, input: args, output: out}}
end
```

**Step 5: Same pattern for Claude's `execute_tools_with_log`**

Thread opts through Claude's agent loop. Add the same dangerous tool check before `ReqLLM.Tool.execute/2`.

**Step 6: Run tests**

Run: `mix test`
Expected: PASS

**Step 7: Commit**

```bash
git add lib/ex_calibur/llm/ollama.ex lib/ex_calibur/llm/claude.ex lib/ex_calibur/step_runner.ex test/ex_calibur/step_runner/dangerous_tool_interception_test.exs
git commit -m "feat: wire dangerous tool interception into LLM agent loops"
```

---

### Task 4: Verdict Gates in Quest Runner

**Files:**
- Modify: `lib/ex_calibur/quest_runner.ex:50-125`
- Create: `test/ex_calibur/quest_runner/verdict_gate_test.exs`

**Step 1: Write failing test**

```elixir
# test/ex_calibur/quest_runner/verdict_gate_test.exs
defmodule ExCalibur.QuestRunner.VerdictGateTest do
  use ExUnit.Case, async: true

  alias ExCalibur.QuestRunner

  describe "check_gate/2" do
    test "no gate field passes through" do
      step_entry = %{"step_id" => "1", "order" => 1}
      result = {:ok, %{verdict: "fail", steps: []}}
      assert :continue = QuestRunner.check_gate(step_entry, result)
    end

    test "gate true with pass verdict continues" do
      step_entry = %{"step_id" => "1", "order" => 1, "gate" => true}
      result = {:ok, %{verdict: "pass", steps: []}}
      assert :continue = QuestRunner.check_gate(step_entry, result)
    end

    test "gate true with fail verdict blocks" do
      step_entry = %{"step_id" => "1", "order" => 1, "gate" => true}
      result = {:ok, %{verdict: "fail", steps: [%{results: [%{reason: "tests broken"}]}]}}
      assert {:gated, _reason} = QuestRunner.check_gate(step_entry, result)
    end

    test "gate true with abstain continues" do
      step_entry = %{"step_id" => "1", "order" => 1, "gate" => true}
      result = {:ok, %{verdict: "abstain", steps: []}}
      assert :continue = QuestRunner.check_gate(step_entry, result)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_calibur/quest_runner/verdict_gate_test.exs`
Expected: FAIL — function not defined

**Step 3: Implement `check_gate/2`**

Add to `lib/ex_calibur/quest_runner.ex`:

```elixir
def check_gate(%{"gate" => true}, {:ok, %{verdict: "fail"} = result}) do
  reason =
    result
    |> Map.get(:steps, [])
    |> Enum.flat_map(&Map.get(&1, :results, []))
    |> Enum.map_join("; ", &Map.get(&1, :reason, ""))

  {:gated, reason}
end

def check_gate(_, _), do: :continue
```

**Step 4: Wire into the step iteration loop**

In `do_run/2`, after `result = StepRunner.run(resolved_step, current_input)` and the logging/learning loop code, add gate check. If gated, skip to the last step:

```elixir
# After getting result and logging, check gate
case check_gate(step, result) do
  {:gated, reason} ->
    Logger.info("[QuestRunner] GATED at step #{resolved_step.name}: #{reason}")

    blocked_text = """
    ## BLOCKED
    **Gated step:** #{resolved_step.name}
    **Verdict:** fail
    **Reason:** #{reason}

    The quest was halted because this gate step returned a fail verdict.
    Review the findings above and decide how to proceed.
    """

    blocked_input = "#{current_input}\n\n#{blocked_text}"

    # Skip to last step
    last_step_entry = List.last(ordered_steps)
    last_step_id = last_step_entry["step_id"] || last_step_entry["quest_id"]

    last_result =
      case resolve_step(last_step_id) do
        nil -> {:error, :step_not_found}
        last_step -> StepRunner.run(last_step, blocked_input)
      end

    # Return immediately with gated status
    throw({:gated, acc_results ++ [result, last_result]})

  :continue ->
    # existing handoff logic
    ...
end
```

Wrap the `Enum.reduce` in a `try/catch` for the `:gated` throw, and set quest run status to `"gated"`.

**Step 5: Run tests**

Run: `mix test test/ex_calibur/quest_runner/verdict_gate_test.exs`
Expected: PASS

Run: `mix test`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/ex_calibur/quest_runner.ex test/ex_calibur/quest_runner/verdict_gate_test.exs
git commit -m "feat: add verdict gates to quest runner — fail stops pipeline"
```

---

### Task 5: Rollback on Failure in Step Runner

**Files:**
- Modify: `lib/ex_calibur/step_runner.ex`
- Create: `test/ex_calibur/step_runner/rollback_test.exs`

**Step 1: Write failing test**

```elixir
# test/ex_calibur/step_runner/rollback_test.exs
defmodule ExCalibur.StepRunner.RollbackTest do
  use ExUnit.Case, async: true

  alias ExCalibur.StepRunner

  describe "has_write_tools?/1" do
    test "detects write tools in loop_tools" do
      assert StepRunner.has_write_tools?(["run_sandbox", "write_file", "read_file"])
    end

    test "returns false for read-only tools" do
      refute StepRunner.has_write_tools?(["run_sandbox", "read_file", "query_lore"])
    end

    test "returns false for empty list" do
      refute StepRunner.has_write_tools?([])
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_calibur/step_runner/rollback_test.exs`
Expected: FAIL

**Step 3: Implement rollback helpers**

Add to `lib/ex_calibur/step_runner.ex`:

```elixir
@write_tool_names ~w(write_file edit_file git_commit create_obsidian_note daily_obsidian)

def has_write_tools?(loop_tools) when is_list(loop_tools) do
  Enum.any?(loop_tools, &(&1 in @write_tool_names))
end

def has_write_tools?(_), do: false

defp git_snapshot do
  case System.cmd("git", ["stash", "create"], stderr_to_stdout: true) do
    {ref, 0} -> {:ok, String.trim(ref)}
    _ -> :no_snapshot
  end
end

defp git_rollback do
  Logger.info("[StepRunner] Rolling back uncommitted changes")
  System.cmd("git", ["checkout", "--", "."], stderr_to_stdout: true)
  # Also clean untracked files written by tools
  System.cmd("git", ["clean", "-fd", "--exclude=_build", "--exclude=deps", "--exclude=.elixir_ls"],
    stderr_to_stdout: true
  )
end
```

**Step 4: Wrap freeform run with rollback**

In the `run(%{output_type: "freeform"} = quest, input_text)` function, wrap the `call_member_raw` call:

```elixir
should_rollback = has_write_tools?(quest.loop_tools || [])
if should_rollback, do: git_snapshot()

case call_member_raw(member, augmented, opts) do
  {raw, tool_calls} when is_binary(raw) ->
    {:ok, %{output: raw, member: member.name, tool_calls: tool_calls}}

  nil ->
    if should_rollback, do: git_rollback()
    {:error, :llm_failed}
end
```

Also check for max_iterations in the result — if the LLM returned due to hitting max iterations (indicated by an empty response), trigger rollback. The Ollama loop returns `{:ok, "", tool_log}` when max iterations hit with no final answer. Check for this in `call_member_raw`:

```elixir
{raw, tool_calls} when is_binary(raw) and raw == "" ->
  if should_rollback do
    Logger.info("[StepRunner] Empty response after tool iterations — rolling back")
    git_rollback()
  end
  {:ok, %{output: raw, member: member.name, tool_calls: tool_calls}}
```

**Step 5: Run tests**

Run: `mix test test/ex_calibur/step_runner/rollback_test.exs`
Expected: PASS

Run: `mix test`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/ex_calibur/step_runner.ex test/ex_calibur/step_runner/rollback_test.exs
git commit -m "feat: rollback uncommitted changes when step fails or hits max iterations"
```

---

### Task 6: Styler Guard in git_commit Tool

**Files:**
- Modify: `lib/ex_calibur/tools/git_commit.ex`
- Create: `test/ex_calibur/tools/git_commit_test.exs`

**Step 1: Write failing test**

```elixir
# test/ex_calibur/tools/git_commit_test.exs
defmodule ExCalibur.Tools.GitCommitTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Tools.GitCommit

  test "req_llm_tool returns valid tool struct" do
    tool = GitCommit.req_llm_tool()
    assert tool.name == "git_commit"
    assert "files" in tool.parameter_schema["required"]
  end
end
```

**Step 2: Add Styler guard to git_commit**

Modify `lib/ex_calibur/tools/git_commit.ex`:

```elixir
def call(%{"files" => files, "message" => message} = params) do
  working_dir = Map.get(params, "working_dir", File.cwd!())

  # Stage files
  Enum.each(files, fn file ->
    System.cmd("git", ["add", file], cd: working_dir, stderr_to_stdout: true)
  end)

  # Styler guard: auto-format staged Elixir files before committing
  elixir_files = Enum.filter(files, &String.ends_with?(&1, ".ex"))

  if elixir_files != [] do
    System.cmd("mix", ["format" | elixir_files], cd: working_dir, stderr_to_stdout: true)
    # Re-stage formatted files
    Enum.each(elixir_files, fn file ->
      System.cmd("git", ["add", file], cd: working_dir, stderr_to_stdout: true)
    end)
  end

  case System.cmd("git", ["commit", "-m", message], cd: working_dir, stderr_to_stdout: true) do
    {output, 0} -> {:ok, "Committed: #{String.trim(output)}"}
    {output, _} -> {:error, "Commit failed: #{output}"}
  end
end
```

**Step 3: Run tests**

Run: `mix test test/ex_calibur/tools/git_commit_test.exs`
Expected: PASS

Run: `mix test`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/ex_calibur/tools/git_commit.ex test/ex_calibur/tools/git_commit_test.exs
git commit -m "feat: auto-format Elixir files before git commit (Styler guard)"
```

---

### Task 7: Update Quest Seed with Guardrail Config

**Files:**
- Modify: `lib/ex_calibur/self_improvement/quest_seed.ex`

**Step 1: Add `dangerous_tool_mode` to step definitions**

Update step attrs in `create_steps/0`:

```elixir
# SI: PM Triage — add:
dangerous_tool_mode: "intercept",
max_tool_iterations: 10,

# SI: Code Writer — keep execute (needs git_commit, open_pr):
dangerous_tool_mode: "execute",
max_tool_iterations: 15,

# SI: Code Reviewer — add:
dangerous_tool_mode: "intercept",
max_tool_iterations: 10,

# SI: QA — safe tools only, but cap iterations:
max_tool_iterations: 10,

# SI: UX Designer — safe tools only:
max_tool_iterations: 10,

# SI: PM Merge Decision — add:
dangerous_tool_mode: "intercept",
max_tool_iterations: 10,
```

**Step 2: Add gate flags to quest step entries**

In `create_quest/2`, update step entries to include gates:

```elixir
step_entries =
  steps
  |> Enum.with_index(1)
  |> Enum.map(fn {step, order} ->
    base = %{"step_id" => step.id, "order" => order}

    # Gate on Code Reviewer (step 3) and QA (step 4)
    if step.name in ["SI: Code Reviewer", "SI: QA"] do
      Map.put(base, "gate", true)
    else
      base
    end
  end)
```

**Step 3: Update sweep step**

```elixir
# SI: Product Analyst Sweep — add:
dangerous_tool_mode: "intercept",
max_tool_iterations: 10,
```

**Step 4: Run tests**

Run: `mix test`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_calibur/self_improvement/quest_seed.ex
git commit -m "feat: configure SI steps with interception, gates, and iteration caps"
```

---

### Task 8: Integration Test

**Files:**
- Create: `test/ex_calibur/quest_runner/guardrails_integration_test.exs`

**Step 1: Write integration test that verifies the full flow**

```elixir
# test/ex_calibur/quest_runner/guardrails_integration_test.exs
defmodule ExCalibur.QuestRunner.GuardrailsIntegrationTest do
  use ExCalibur.DataCase, async: false

  alias ExCalibur.QuestRunner
  alias ExCalibur.Quests

  describe "verdict gate integration" do
    test "quest with gated step that fails skips to final step" do
      # Create a step with output_type verdict that will return fail
      {:ok, gate_step} = Quests.create_step(%{
        name: "Test Gate Step",
        trigger: "manual",
        output_type: "verdict",
        roster: []
      })

      {:ok, final_step} = Quests.create_step(%{
        name: "Test Final Step",
        trigger: "manual",
        output_type: "freeform",
        roster: []
      })

      # Verify check_gate detects fail
      result = {:ok, %{verdict: "fail", steps: [%{results: [%{reason: "bad code"}]}]}}
      step_entry = %{"step_id" => to_string(gate_step.id), "order" => 1, "gate" => true}

      assert {:gated, _reason} = QuestRunner.check_gate(step_entry, result)
    end
  end
end
```

**Step 2: Run integration test**

Run: `mix test test/ex_calibur/quest_runner/guardrails_integration_test.exs`
Expected: PASS

**Step 3: Run full suite**

Run: `mix test`
Expected: PASS

**Step 4: Commit**

```bash
git add test/ex_calibur/quest_runner/guardrails_integration_test.exs
git commit -m "test: add guardrails integration tests"
```
