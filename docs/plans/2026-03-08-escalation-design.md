# Escalation Design

**Date:** 2026-03-08

## Goal

Allow quest rosters to chain evaluation steps across local Ollama members and cloud Claude tiers, routing to the next step based on configurable escalation conditions.

## Roster Step Schema

Each roster step gets an optional `escalate_on` field:

```elixir
%{
  who: :apprentice | :journeyman | :master | :all | member_id | :claude_haiku | :claude_sonnet | :claude_opus,
  when: :on_trigger | :on_escalation,
  how: :solo | :consensus | :unanimous | :first_to_pass,
  escalate_on: {:verdict, [:warn, :fail]} | {:confidence, float()} | :always | :never
}
```

## Escalation Conditions

- `{:verdict, [verdicts]}` — escalate if aggregate verdict matches any in list
- `{:confidence, threshold}` — escalate if aggregate confidence below threshold
- `:always` — always continue to next step (pipeline/waterfall)
- `:never` — stop here (default if omitted)

## Claude Tiers as Virtual Members

`:claude_haiku`, `:claude_sonnet`, `:claude_opus` are not DB members — they are resolved at evaluation time by the Evaluator. Config:

```elixir
config :ex_cellence_server, :anthropic,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  base_url: "https://api.anthropic.com"
```

Model IDs: `claude-haiku-4-5-20251001`, `claude-sonnet-4-6`, `claude-opus-4-6`.

The Evaluator checks `who` — if `:claude_*`, calls Anthropic API via `req` with the same ACTION/CONFIDENCE/REASON prompt format. Response is parsed identically to Ollama.

## Escalation Flow

```
Step 1 runs → aggregate verdict + confidence computed
  → check escalate_on condition
    → condition met + next step exists → run Step 2 with :on_escalation
    → condition not met OR no next step → return result
```

Final result carries: final verdict, final confidence, full step-by-step trace (who ran, what they returned, why escalated).

## Out of Scope (v1)

- Per-member escalation (escalation is per-step, not per-member within a step)
- Cost tracking for Claude API calls (add later)
- Fallback on API error (fails the quest run for now)
