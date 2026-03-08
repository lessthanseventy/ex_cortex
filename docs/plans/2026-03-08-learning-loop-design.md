# Learning Loop Design

**Date:** 2026-03-08

## Goal

Allow the system to review its own quest run outcomes and propose — or automatically apply — small improvements to member config, escalation thresholds, and quest rosters over time.

## Architecture

A `retrospective` quest type runs on a schedule (configurable, e.g. `@daily`). It:
1. Pulls recent quest run data (verdicts, confidence, escalation frequency, outcome accuracy)
2. Sends it to a master-tier member or Claude for analysis
3. Parses the response into structured proposed changes
4. Auto-applies small changes; queues large changes for human approval

## Proposed Changes Schema

New `excellence_proposals` table:

| field | type |
|-------|------|
| id | uuid |
| source | string — e.g. "retrospective:quest-id" |
| type | string — "member_config" \| "quest_roster" \| "threshold" \| "system_prompt" |
| target_id | string — member or quest ID |
| current_value | map |
| proposed_value | map |
| reason | text |
| status | string — "pending" \| "approved" \| "rejected" \| "applied" |
| inserted_at | utc_datetime |

## Auto-Apply vs. Approval Queue

**Auto-apply (no user action needed):**
- Confidence threshold nudge ≤ ±0.05
- Model swap within same tier (e.g. phi4-mini → gemma3:4b, both apprentice)
- Escalation condition threshold nudge ≤ ±0.05

**Approval queue (user must approve):**
- System prompt edits
- Roster step additions/removals
- Member rank changes
- Escalation path changes (adding/removing Claude tiers)
- Member enable/disable

## Lodge UI

New "Proposals" card in Lodge shows pending approvals:
- What changed, why, who proposed it
- One-click Approve / Reject
- Auto-applied changes shown in a collapsed "Recent Auto-Tuning" log

## Retrospective Quest Format

The retrospective quest renders a data summary as input and uses a master/Claude member with a system prompt like:

```
You are a performance analyst for an AI evaluation system. Review the provided quest run
statistics and identify 1-3 specific, actionable improvements. For each, output a JSON block:

{"type": "threshold", "target_id": "quest-id", "field": "escalate_on.confidence", "current": 0.70, "proposed": 0.65, "reason": "..."}
```

The Evaluator parses these JSON blocks from the response and creates proposal records.

## Out of Scope (v1)

- Cross-quest learning (retrospective is per-quest)
- Automatic rollback if auto-applied change degrades performance
- Approval notifications (email/webhook)
- Proposal history / audit trail beyond status field
