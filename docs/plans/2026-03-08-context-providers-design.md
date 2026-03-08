# Context Providers Design

**Date:** 2026-03-08

## Goal

Allow quests to inject structured context blocks alongside the input text at evaluation time, so agents have richer information than just the raw source item.

## Quest-Level Config

```elixir
context_providers: [
  %{type: :quest_history, quest_id: "some-quest-id", limit: 5},
  %{type: :member_stats, window: "7d"},
  %{type: :static, content: "This source is high-priority. Flag anything ambiguous."}
]
```

## Provider Types (v1)

### `:quest_history`
Fetches last N completed quest runs for a given quest, formats as a summary block:
```
=== Recent Evaluations (last 5) ===
2026-03-07 14:00 — PASS (confidence: 0.82) — "No issues found."
2026-03-07 10:00 — WARN (confidence: 0.61) — "Minor formatting issues."
...
```

### `:member_stats`
Fetches aggregate verdict accuracy per member over a time window:
```
=== Member Performance (last 7 days) ===
wcag-auditor (master): 12 runs, 83% agree with final verdict
usability-reviewer (journeyman): 8 runs, 75% agree with final verdict
...
```

### `:static`
Injects a hardcoded string as-is. Useful for domain context, source metadata, standing instructions.

## Prompt Assembly

At run time, context blocks are assembled in order and prepended to the input:

```
[context block 1]

[context block 2]

=== Input ===
[source item content]
```

## Extension Point

A `ExCellenceServer.ContextProvider` behaviour for app-level custom providers:

```elixir
@callback fetch(config :: map(), quest_run :: map()) :: String.t()
```

Custom providers registered in config:
```elixir
config :ex_cellence_server, :context_providers, [
  my_app: MyApp.CustomContextProvider
]
```

## Out of Scope (v1)

- Per-member context (all members in a step get the same context)
- Dynamic provider chaining (providers run independently and are concatenated)
- Token budget enforcement (no truncation logic yet)
