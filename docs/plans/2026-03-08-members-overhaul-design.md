# Members Page Overhaul Design

**Date:** 2026-03-08

## Goal

Unify built-in members (from `Member.all()`) and custom DB members (ResourceDefinition) into a single page with collapsible card rows, inline config editing, and a copper/silver/gold rank color hierarchy.

## Data Model

Built-ins (`Member.all()`) and custom members (`ResourceDefinition`) are merged at query time — no DB seeding required.

**Merged shape:**
- `id` — built-in slug or UUID for custom
- `name`, `description`, `category`
- `active` — boolean (derived from ResourceDefinition status or absence)
- `system_prompt`
- `ranks` — map with three keys: `apprentice`, `journeyman`, `master`, each `{model, strategy}`

**DB strategy:**
- Built-in with no DB record → inactive, default config from `Member.all()`
- Toggling a built-in on or editing it → upserts a `ResourceDefinition` with `source: "builtin"`, `config["member_id"]` = built-in ID
- Custom members → `source: "db"`, no `member_id` in config
- Status mapping: `"active"` → active=true, everything else → active=false

## Card UI

### Collapsed state
```
[›] Member Name          [Editor]   [◆ phi4-mini] [◆ gemma3:4b] [◆ llama3:8b]   [toggle]
                                     Apprentice     Journeyman     Master
```

- Chevron left, name + category badge middle-left
- Three rank pills (copper/silver/gold) in middle-right
- Active/inactive toggle switch far right
- Inactive cards: `opacity-60`

### Expanded state
- Editable name field (custom members only; built-ins show name as heading)
- System prompt textarea (full width)
- Three rank sections side-by-side:
  - Colored header bar with rank name
  - Model text input
  - Strategy select: `cot` / `cod` / `default`
- Save button + Delete button (destructive) at bottom right
- Explicit save (not auto-save on blur) to avoid accidental overwrites

### New member
- `+` button top right of page
- Opens a blank custom card inline at top of list, expanded by default

## Sorting
1. Active members first
2. Within active: built-ins before custom, alphabetical
3. Inactive members second, same sub-sort

## Rank Color Treatment

| Rank | Border | Label | Pill background |
|------|--------|-------|-----------------|
| Apprentice | `border-amber-700` | `text-amber-700` | `bg-amber-50` |
| Journeyman | `border-slate-400` | `text-slate-500` | `bg-slate-100` |
| Master | `border-yellow-500` | `text-yellow-600` | `bg-yellow-50` |

- Collapsed pills: `border-l-2` + rank name + truncated model name
- Expanded rank sections: subtle colored top border on each section card
- Category badges: neutral `variant="outline"` — metadata, not status

## Key Files

- `lib/ex_calibur_web/live/members_live.ex` — main LiveView (full rewrite)
- `lib/ex_calibur/members/member.ex` — built-in definitions (unchanged)
- No new files needed; the `ResourceDefinition` schema handles persistence as-is

## Out of Scope

- No separate Library/install flow for built-ins (toggle on = installed)
- No auto-save on blur
- No rank color changes beyond the three defined above
