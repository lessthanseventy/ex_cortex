# Lore — Design

**Date:** 2026-03-08
**Status:** Ready for implementation

---

## Overview

A persistent, queryable memory layer for the guild. Quests can write synthesized artifacts to the board (summaries, changelogs, ranked news, etc.) and later quests can read those entries as context. Humans can also manually create, edit, and delete entries — giving the board a "curated memory" feel rather than a pure AI dump.

---

## Data Model

### Quest changes

Two new fields on `excellence_quests`:

| Field | Type | Default | Notes |
|---|---|---|---|
| `output_type` | string | `"verdict"` | `"verdict"` or `"artifact"` |
| `write_mode` | string | `"append"` | `"append"` or `"replace"`. Only used when `output_type == "artifact"` |
| `entry_title_template` | string | nil | e.g. `"PR changelog — {date}"`. Supports `{date}` substitution |

### New table: `lore_entries`

| Field | Type | Notes |
|---|---|---|
| `id` | integer | |
| `quest_id` | integer | nullable — nil for manual entries |
| `title` | string | required |
| `body` | text | markdown |
| `tags` | `{:array, :string}` | default `[]` |
| `importance` | integer | 1–5, nullable = unranked |
| `source` | string | `"quest"` or `"manual"`. Manual entries (or quest entries that have been human-edited) are never auto-overwritten |
| `inserted_at` / `updated_at` | | |

### Replace-mode overwrite rule

A replace-mode artifact quest may only overwrite an existing entry if:
- `entry.quest_id == quest.id` AND
- `entry.source == "quest"` (not manually edited)

---

## Quest Config Changes

On the Quests page, create/edit quest form adds:

**Output** selector (new field, shown after Trigger):
- `Verdict` — default, existing behavior (roster evaluates → pass/warn/fail)
- `Artifact` — roster synthesizes → writes to lore

When `Artifact` is selected:
- **Escalate on** field is hidden (no verdict to escalate on)
- **Write mode** appears: `Append` / `Replace`
- **Entry title template** appears: text input, placeholder `"Summary — {date}"`

The quest `description` field acts as the synthesis instruction — what the members should produce. Example: *"Summarize the top a11y news stories from this week, ranked by importance to a Phoenix developer."*

### Roster behaviour for artifact quests

- `who` and `how` still apply (e.g. solo senior member synthesizes, or consensus across two)
- The LLM response is parsed as structured output: title, body, tags[], importance
- If parsing fails, the raw response is stored as body with a generated title

---

## Lore Page — `/lore`

New page in the nav (between Lodge and Library, roughly).

### Layout

Header: **Lore** + `+ New Entry` button.

Filter bar:
- Tag filter (multi-select badges, click to toggle)
- Quest filter (dropdown: All quests / specific quest)
- Sort: `Newest` / `Highest importance`

Entry feed (cards, newest first by default):

```
┌─────────────────────────────────────────────────────────┐
│ ● ● ● ● ○  PR Changelog — week of 2026-03-08            │
│                                                          │
│  Merged this week: 14 PRs across 3 repos. Notable:      │
│  - phoenix_live_view 1.0.1 — fixes flash hook…          │
│  - salad_ui 0.13 — new sheet component…                 │
│                                                          │
│  [code-review] [deps] [weekly]                           │
│  From: PR Watcher Quest · 2026-03-08 09:00   [Edit] [✕] │
└─────────────────────────────────────────────────────────┘
```

- Importance shown as 1–5 filled dots (○●)
- Tags as clickable badge filters
- Footer: quest name (or "Manual") + timestamp
- Replace-mode entries show "Last updated" instead of created timestamp
- Human-curated entries (source: manual) get a small ✎ indicator

### Manual entry form (inline, triggered by `+ New Entry`)

Fields: Title, Body (textarea, markdown), Tags (comma-separated input), Importance (1–5 select or none).

### Edit (inline expand on card)

Same fields. Saving sets `source: "manual"` — the entry won't be auto-overwritten by a quest again.

### Delete

Confirmation required. For quest-owned entries, a note: *"This entry will be re-generated on the next quest run unless you change the quest's write mode."*

---

## Read-back: Lore as Context Provider

The `context_providers` array on quests gains a new type:

```json
{"type": "lore", "tags": ["a11y"], "limit": 10, "sort": "importance"}
```

| Option | Type | Default | Notes |
|---|---|---|---|
| `tags` | string[] | `[]` | Empty = all entries |
| `limit` | integer | 10 | Max entries to inject |
| `sort` | string | `"newest"` | `"newest"` or `"importance"` |

At run time, the provider queries `lore_entries`, formats matching entries into a structured markdown block injected as prompt context:

```
## Lore Context
### PR Changelog week of 2026-03-08 [importance: 4]
Tags: code-review, deps
Merged this week: 14 PRs...

### a11y News — 2026-03-01 [importance: 5]
Tags: a11y, weekly
Top stories: ...
```

### Quest form changes

The Context dropdown (None / Static text / Quest history / Member roster) gains:

**Knowledge board** — when selected, shows:
- Tag filter input (comma-separated)
- Limit input (default 10)
- Sort selector (Newest / Highest importance)

---

## Data Flow Summary

```
Sources
  └─► Artifact Quest ──► lore_entries (append or replace)
                               │
                               ▼
                         Lore UI  ◄──► Manual CRUD
                               │
                               ▼
              context_providers: lore
                               │
                               ▼
                    Verdict Quest (enriched context)
                               │
                        pass / warn / fail
```

---

## Implementation Plan (rough order)

1. Migration: add `output_type`, `write_mode`, `entry_title_template` to `excellence_quests`
2. Migration: create `lore_entries` table
3. `KnowledgeEntry` schema + `Knowledge` context module (CRUD)
4. Quest run handler: detect `output_type == "artifact"`, write/replace entry instead of verdict
5. `/lore` LiveView: list, filter, sort, manual CRUD
6. Quests form: output type, write mode, title template fields
7. Context provider: `lore` type in quest run context assembly
8. Quests form: lore context option with tag/limit/sort inputs
9. Tests

---

## Out of Scope (future)

- Pinning entries to prevent any overwrite
- Entry versioning / diff history
- Exporting the board as markdown/JSON
- Cross-guild knowledge sharing
