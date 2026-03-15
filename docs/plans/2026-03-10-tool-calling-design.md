# Tool Calling Design

**Date:** 2026-03-10
**Status:** Draft

## Problem

Members and Steps are currently single-shot: one LLM call in, one verdict/artifact out. There's no mechanism for a model to gather information before responding, for a step to retry with better context, or for escalating to more capable models when confidence is low.

## Goals

- Give LLMs a tool surface they can call during response generation (member-level agent loop)
- Allow steps to reflect (gather context, re-run) and escalate (try higher-ranked members) when results are unsatisfying
- Keep dangerous tools gated behind an explicit opt-in ("YOLO mode")
- Don't change the external contract of Steps — they still return `%{verdict, steps}` or `%{artifact}` regardless of how many iterations ran internally

## Out of Scope (for now)

- Free-form web search / browsing (too dangerous without tighter scoping)
- Persistent agent state across quest runs
- A meta-orchestrator that reasons about its own strategy (interesting future direction)

---

## Architecture

### Tool Registry

Tools are Elixir functions with metadata that serialises into the LLM's native tool-calling format (Claude tool use blocks / Ollama function calling).

```elixir
defmodule ExCortex.Tools.Tool do
  defstruct [:name, :description, :parameters, :handler, :safe?]
end
```

**Safe tools** (always available when tools are enabled):

| Tool | Description |
|------|-------------|
| `run_quest` | Run a quest with given input, return result |
| `query_lore` | Read artifacts from the lore store |
| `write_artifact` | Write an artifact to lore |
| `call_herald` | Trigger a herald delivery |

**YOLO tools** (opt-in, requires `yolo: true` on member or step config):

| Tool | Description |
|------|-------------|
| `fetch_url` | Hit an external URL and return the body |
| `run_code` | Execute an Elixir expression in a sandbox |
| `read_file` | Read a file from the filesystem |

Each tool execution runs in an isolated `Task` with a timeout. If a tool crashes or times out, the LLM receives an error result and the loop continues — nothing in the supervision tree is affected.

Tool availability is declared in member or step config:

```elixir
tools: ["run_quest", "query_lore"]  # specific tools
tools: :all_safe                    # all safe tools
tools: :yolo                        # safe + YOLO tools
```

---

### Member-Level Agent Loop

The current `call_member/3` is a single LLM call. With tools, it becomes a recursive loop:

```
call model with tool definitions
  ├── model returns tool_calls
  │     execute in parallel Tasks (with timeout)
  │     feed results back as tool_result messages
  │     repeat (up to max_iterations)
  └── model returns final text
        parse verdict / artifact as normal
```

Loop state is an accumulating message list — no GenServer, just a recursive function. Tool calls within a single iteration execute concurrently via `Task.async_stream`.

Member config gains:

```elixir
%{
  type: :claude,
  tier: "claude_sonnet",
  tools: :all_safe,
  max_iterations: 5   # hard cap, default 5
}
```

The member loop is transparent to the Step — it still returns the same result shape regardless of how many iterations ran internally.

---

### Step-Level Loops

Steps gain two optional loop behaviors, configured independently and composable.

#### Reflect Mode

The orchestrator (StepRunner) decides to retry when a result is unsatisfying. The model itself does not drive this — the step logic does.

Flow:
1. Run members normally
2. If result is unsatisfying (confidence below threshold, or verdict in trigger list):
   - Execute reflect tools to gather more context
   - Re-run members with augmented input
3. Repeat up to `max_iterations`
4. Return best result

"Unsatisfying" is configurable:

```elixir
reflect: true,
reflect_threshold: 0.6,          # confidence below this triggers reflect
reflect_on_verdict: ["warn"],     # or verdict-based
reflect_tools: ["query_lore"],    # tools available during reflect phase
max_iterations: 3
```

#### Escalate Mode

A simple rank ladder: apprentice → journeyman → master. Short-circuits as soon as the result is satisfying.

Flow:
1. Run with current rank members
2. If result is unsatisfying: re-run with next rank up
3. Repeat until master or result is satisfying
4. Return best result

```elixir
escalate: true,
escalate_threshold: 0.6,         # confidence below this triggers escalation
escalate_on_verdict: ["warn"],   # or verdict-based
```

Reuses `resolve_by_rank/1` from StepRunner — no new member resolution logic needed.

#### Composition

Both modes can be active on the same step. Execution order:

```
plan phase (if loop_mode: "plan")
  → run members
    → reflect (if enabled and result unsatisfying)
      → escalate (if enabled and result still unsatisfying)
        → return best result
```

Full step config example:

```elixir
%{
  roster: [...],
  loop_mode: "reflect",            # nil | "reflect" | "plan"
  loop_tools: ["query_lore", "run_quest"],
  reflect_threshold: 0.6,
  reflect_on_verdict: ["warn"],
  escalate: true,
  escalate_threshold: 0.5,
  yolo: false,
  max_iterations: 5
}
```

---

### Plan Mode (Step-Level)

Before invoking members, a planning phase runs: a lightweight LLM call (or pure logic) that calls tools to assemble context, then hands off enriched input to the normal member roster.

This is declared with `loop_mode: "plan"` on the step. The planner uses the same tool execution infrastructure as reflect mode.

---

## OTP Shape

No new supervision tree entries required.

- **StepRunner** stays a plain module (no process)
- **Tool execution** uses `Task.async_stream` for parallel calls with per-tool timeouts
- **Tools that need persistence** (e.g. `RunQuest`, `WriteArtifact`) delegate to existing supervised processes
- **Agent loop state** is a plain recursive function accumulating a message list — no GenServer needed unless live observability of loop state is added later

---

## Implementation Order

1. **Tool struct + registry** — define the Tool struct, implement safe tools, wire up tool serialisation for Claude and Ollama
2. **Member-level loop** — replace `call_member` single-call with the iterative loop for members that declare tools
3. **Escalate mode** — add escalation ladder to StepRunner, reusing existing rank resolution
4. **Reflect mode** — add reflect loop to StepRunner, using tool infrastructure from step 1
5. **Plan mode** — add planning phase to StepRunner
6. **YOLO tools** — implement YOLO tool set behind the `yolo: true` flag
7. **UI** — expose loop_mode, tools, escalate, yolo in the Quests UI step editor
