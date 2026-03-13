# Self-Improvement Loop Guardrails Design

**Date:** 2026-03-12
**Scope:** Structural guardrails for the self-improvement quest pipeline

## Problem

The self-improvement loop has five failure modes observed in production runs:

1. **No verdict gates** — quest continues through all steps even when Code Reviewer abstains and QA fails, allowing PM Merge Decision to take real actions (e.g., closing GitHub issues) on broken work
2. **Wasted iterations** — models burn 15 tool iterations calling `search_github` repeatedly with empty results
3. **Dangerous tools fire without approval** — `close_issue`, `git_push` execute immediately; `intercept_dangerous_tool()` exists in step_runner.ex but is never called
4. **Models write broken code with no rollback** — QA wrote a test referencing a nonexistent function, left it in the repo, exhausted iterations trying to fix it
5. **Styler fights** — models make formatting-only commits that Styler would immediately revert

## Solution: Five Structural Guardrails

### 1. Verdict Gates in Quest Runner

Add a `"gate"` field to quest step entries. When a step has `"gate": true` and its verdict is `fail`, the quest runner:

- Skips all subsequent steps **except** the final step
- Passes a `## BLOCKED` handoff block to the final step explaining which gate failed and why
- Sets quest run status to `"gated"` (distinct from `"failed"`)

**Gated SI steps:**
- SI: Code Reviewer → `"gate": true`
- SI: QA → `"gate": true`

**Abstain behavior:** Treated as a soft pass — quest continues but handoff notes the abstention. Only `fail` triggers the gate.

**Step entry format:**
```elixir
%{"step_id" => step.id, "order" => 3, "gate" => true}
```

### 2. Dangerous Tool Interception

Wire `intercept_dangerous_tool()` into the tool execution path. Three modes configurable per step:

- `"execute"` — current behavior, tools fire immediately (default)
- `"intercept"` — dangerous tools create a Lodge proposal, LLM receives: `"Tool call queued for human approval. Proposal ID: {id}. Continue without this result."`
- `"dry_run"` — dangerous tools return: `"DRY RUN: Would have called {tool_name} with {args}. No action taken."`

**SI step assignments:**
| Step | Mode | Reason |
|------|------|--------|
| SI: PM Triage | intercept | Could hit close_issue, merge_pr |
| SI: Code Writer | execute | Needs git_commit, open_pr to function |
| SI: Code Reviewer | intercept | Should comment, not merge/close |
| SI: QA | execute | Only uses run_sandbox, read_file |
| SI: UX Designer | execute | Only uses run_sandbox |
| SI: PM Merge Decision | intercept | Closed a real issue in observed run |
| SI: Analyst Sweep | intercept | Files GitHub issues — should be reviewed |

**Hook location:** In Ollama and Claude agent loops, before `ReqLLM.Tool.execute()`. Check if tool is in dangerous tier and what mode the step is configured for. Mode flows via `opts` map through `complete_with_tools/4`.

### 3. Iteration Circuit Breaker

Track tool call results within the agent loop. If the **same tool** returns empty/error results **3 times consecutively**, auto-skip further calls and inject: `"Tool {name} returned empty results 3 times. Skipping — proceed with available information."`

**Implementation:** Simple map in agent loop: `%{tool_name => consecutive_empty_count}`. Reset on non-empty result.

**What counts as empty:** `[]`, `""`, `nil`, strings matching `"Error:"`, the `"[]\n"` pattern.

**Per-step max_tool_iterations:** New field defaulting to 10 for SI steps (down from Ollama's global 15).

### 4. Rollback on Failure

When a step has write tools and exits uncleanly, restore the working directory.

**Mechanism:**
1. Before step runs (if write tools available): `git stash create` to snapshot
2. After step completes, check outcome:
   - Clean completion → keep changes
   - Max iterations hit with no final answer → `git checkout -- .`
   - Step error → `git checkout -- .`
3. Log: `"[StepRunner] Rolled back uncommitted changes from step {name} (reason: max_iterations)"`

**Edge case:** If model called `git_commit` during the step, those changes are already committed. `git checkout -- .` only cleans uncommitted changes, which is correct — committed work is the PM Merge Decision's responsibility to evaluate.

**Location:** StepRunner, wrapping roster execution.

### 5. Styler Guard in git_commit Tool

Before committing, auto-format staged files:

1. Run `mix format` on staged files
2. Re-stage the formatted versions
3. Then commit

This ensures every commit is Styler-compliant. Models cannot create formatting-only commits that Styler would revert.

**Location:** `ExCalibur.Tools.GitCommit.call/1`, before the `System.cmd("git", ["commit", ...])` call.

## Files Affected

| File | Change |
|------|--------|
| `lib/ex_calibur/quest_runner.ex` | Verdict gate logic in step iteration loop |
| `lib/ex_calibur/step_runner.ex` | Rollback wrapper, pass dangerous_tool_mode to LLM |
| `lib/ex_calibur/llm/ollama.ex` | Circuit breaker, dangerous tool interception in agent loop |
| `lib/ex_calibur/llm/claude.ex` | Circuit breaker, dangerous tool interception in agent loop |
| `lib/ex_calibur/tools/git_commit.ex` | Styler guard pre-commit formatting |
| `lib/ex_calibur/self_improvement/quest_seed.ex` | Add gate flags, dangerous_tool_mode to step configs |
| `lib/ex_calibur/quests/step.ex` | Add max_tool_iterations, dangerous_tool_mode fields |
