# Quests & Campaigns Design

**Date:** 2026-03-08

## Goal

Replace the stub `/quests` page and `/evaluate` page with a full quest + campaign system — the "meat" of the framework. A quest defines who evaluates incoming content, when, and how they deliberate. A campaign chains quests together into a series with flow control between steps.

## Hierarchy

```
Campaign
  └── Quest Steps (ordered, with flow rules)
        └── Quest
              └── Roster Assignments (who, when, how)
                    └── Quest Run (single execution)
```

## Data Model

### Quest

- `name`, `description`
- `status` — active | paused
- `trigger` — manual | source | scheduled
- `schedule` — cron string (if scheduled, e.g. `"@hourly"`)
- `roster` — ordered list of assignments:
  - `who` — member IDs, or tier atom (`:apprentice` | `:journeyman` | `:master` | `:all`)
  - `when` — `:on_trigger` | `:on_escalation` | `{:schedule, cron}`
  - `how` — `:solo` | `:consensus` | `:unanimous` | `:first_to_pass`
- `source_ids` — list of assigned source IDs (optional)

### Campaign

- `name`, `description`
- `status` — active | paused
- `trigger` — manual | source | scheduled
- `schedule` — cron string (if scheduled)
- `steps` — ordered list:
  - `quest_id`
  - `flow` — `:always` | `:on_flag` | `:on_pass` | `:parallel`
- `source_ids` — list of assigned source IDs (optional)

### Quest Run

- `quest_id`
- `campaign_run_id` (nullable — nil if standalone)
- `input` — the content evaluated
- `status` — pending | running | complete | failed
- `results` — map of member verdicts
- `inserted_at`

### Campaign Run

- `campaign_id`
- `status` — pending | running | complete | failed
- `step_results` — map of quest_id → quest_run_id
- `inserted_at`

## Pre-installed Quests & Campaigns

Each guild charter gains two new functions alongside `resource_definitions/0`:

```elixir
def quest_definitions() :: [map()]
def campaign_definitions() :: [map()]
```

Example for Accessibility Review:
- Quests: "WCAG Hourly Scan" (apprentice, hourly, solo), "Full Accessibility Audit" (all members, manual, consensus)
- Campaign: "Monthly Accessibility Review" — WCAG Scan → (on_flag) → Full Audit

## Pages

### `/quests` — Quest Board

- Lists all campaigns and standalone quests
- Each card shows: name, roster summary, assigned sources, last run + result, active toggle
- "Run now" button → opens inline input panel, runs quest/campaign, streams live results
- "+ New Quest" / "+ New Campaign" inline forms
  - Simple mode: name, who runs it (tier picker), trigger
  - Advanced mode: full roster builder (chain assignments with escalation), campaign step builder
- Absorbs `/evaluate` — "Run now" IS evaluate

### No separate detail page (v1)

Run history shown inline on expansion. Can revisit if history grows complex.

## Guild Hall

- Add "Build your own guild" card — installs blank slate (no members, no quests). User builds from scratch.

## Removing `/evaluate`

- Route redirects to `/quests`
- EvaluateLive module deleted after migration

## Simple / Advanced Mode

**Simple** (default):
- Pick a name
- Who runs it: one of [Apprentice tier / Journeyman tier / Master tier / Everyone]
- How: consensus or solo
- Trigger: manual / source / hourly / daily

**Advanced**:
- Full roster builder — add multiple assignments with `when` and `how` per assignment
- Campaign step builder — add quests, set flow rules between them
- Custom cron schedule

## Out of Scope (v1)

- Webhook output routing on quest completion
- Cross-guild quest sharing
- Quest versioning / history diffing
- Campaign branching (if/else beyond on_flag/on_pass)
