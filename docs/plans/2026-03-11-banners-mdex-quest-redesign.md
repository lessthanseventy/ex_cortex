# Banners, MDEx, and Quest Board Redesign

## Overview

A UX overhaul introducing three major changes:

1. **Banners** — app-wide scoping by domain (Tech, Lifestyle, Business)
2. **Quest board redesign** — quests as recipes with nested collapsible steps and three install paths
3. **MDEx as universal content layer** — all authored content rendered as Markdown with creative use of MDEx's full feature set

## 1. Banner System

### Concept

Banners are a persistent, app-wide scope that filters the entire UI to what's relevant for the user's domain. "Choose your banner" — a thematic framing consistent with the guild terminology.

Three banners:
- **Tech** — Code Review, Incident Triage, PR Review, Security Audit, Architecture Review, API Design, etc.
- **Lifestyle** — Content Moderation, Editorial, Recipe Review, Travel Planning, etc.
- **Business** — Hiring Pipeline, Grant Review, RFP Analysis, Legal Review, Budget Review, etc.

### Behavior

- **First visit:** Town Square presents three banner cards with name, tagline, and preview of contents (e.g. "5 guilds, 12 quests, 8 members"). Picking one stores it and filters the entire app.
- **Switching:** A banner indicator in the top nav shows the current banner. Clicking it returns to Town Square. Switching banners does not uninstall anything — it only changes catalog visibility.
- **Scoping:** Guilds, quest templates, member archetypes, and library books all filter by active banner. Banner-agnostic items (generic/custom) are always visible.

### Data Model

- `settings` table (single-row) with a `banner` column (string, nullable). When `nil`, redirect to Town Square for first-time selection.
- `ExCalibur.Settings` context: `get_banner/0`, `set_banner/1`.
- Each charter, quest template, member archetype, and library book gets a `:banner` tag (`:tech | :lifestyle | :business | nil`). These live on compile-time structs, not in the DB.

## 2. Quest Board Redesign

### Philosophy

Quests are **recipes**. Steps are **ingredients**. The marketplace shows recipes prominently; ingredients are discoverable inside them.

### Three Install Paths

Every quest template card exposes three paths:

1. **"Recruit & Go"** (primary button, path A) — one-click turnkey install. Creates the quest, all its steps, and auto-recruits any missing members at default rank (Journeyman). Fully operational immediately.
2. **"Customize"** (secondary button, path B) — opens the quest with steps as editable collapsible cards. Reorder, remove, tweak steps. Hit "Install" and it still handles all dependencies.
3. **Custom tab** (path C) — power users build from scratch. Unchanged from current.

### Card Design

**Collapsed state (browsing the board):**
- Quest name + banner badge + category badge
- One-line description (MDEx-rendered)
- Step count: "4 steps"
- Readiness pill: "Ready" / "Recruits 2 members" / "Needs: RSS source"
- Two buttons: "Recruit & Go" (primary) and "Customize" (ghost)

**Expanded state (click card or Customize):**
- Full MDEx-rendered description (mermaid diagrams, alerts, checklists)
- Steps as collapsible cards stacked vertically:
  - Each shows: name, description snippet, lore tags in/out
  - Expand for full MDEx-rendered description, roster, output config
  - In customize mode: drag handles, remove, enable/disable toggle
- Suggested team section with missing indicators
- "Install" button at bottom (customize mode)

**Active quest cards** (top of page) use the same structure but swap install buttons for Run Now / Pause / Resume / Delete. Steps show last run status inline.

### Readiness Evolution

Instead of just "Missing: X", readiness indicators communicate what "Recruit & Go" will auto-install:
- "Ready" — everything in place
- "Recruits 2 members" — will auto-recruit, safe to one-click
- "Needs: RSS source" — can't auto-resolve, requires manual setup first

## 3. MDEx as Universal Content Layer

### Baseline

Every piece of authored text becomes Markdown-powered via MDEx `~MD` sigil with HEEX modifier:
- Guild charters
- Member system prompts
- Quest and step descriptions (templates and active)
- Grimoire entries
- Library book descriptions

Content stored as plain Markdown strings. No schema changes. The upgrade is in rendering.

### Creative Uses

- **WikiLinks** — `[[entry-name]]` in grimoire entries links lore entries to each other. `MDEx.WikiLink` nodes rendered as LiveView navigation links via HEEX components.
- **Alerts** — `> [!WARNING]` / `> [!NOTE]` in charters render as styled callout cards. "This guild expects JSON output" type rules.
- **Task items** — `- [x] configure source` / `- [ ] recruit analyst` in quest descriptions render as live readiness checklists.
- **Mermaid diagrams** — quest step flows as `mermaid` code blocks via `mdex_mermaid` plugin. Visual pipeline diagrams render automatically.
- **Emoji shortcodes** — `:shield:` `:scroll:` `:crossed_swords:` in descriptions lean into the guild theme.
- **Front matter** — YAML front matter in charter/template Markdown for structured metadata (banner, category, version). One file = content + config.
- **Streaming fragments** — grimoire entries written by agent evaluation in real-time. MDEx streaming mode renders partial Markdown as it arrives.
- **HEEX components in Markdown** — charter authors embed `<.link>`, status badges, or custom components. A charter could reference `<.member name="analyst"/>` and render a live link.
- **Syntax highlighting** — built-in code fence highlighting for grimoire entries with code snippets, charter rules with example formats, quest descriptions with API payloads.

### Not a Rich Text Editor

This is not about building a Notion clone. Content is stored as plain Markdown strings. Editing stays simple — you write Markdown. The upgrade is in rendering: what's currently flat text gets structure, highlighting, and readability.

## 4. Navigation Changes

### Simplified Nav (6 items, down from 7)

- **Town Square** — banner picker + guild installer
- **Guild Hall** — member roster + charter editing
- **Quests** — quest board (marketplace) + active quests
- **Grimoire** — lore/knowledge base
- **Library** — sources, books, heralds
- **Lodge** — dashboard/monitoring

Guide page becomes a `?` icon or slide-out panel (itself MDEx-rendered).

### Banner Indicator

Sits in the nav (left side or near logo). Shows current banner name + icon/color. Each banner gets a distinct accent color that subtly tints the nav. Clicking navigates to Town Square to switch.

## 5. User Flows

### New User
1. Land on Town Square → choose banner (Tech / Lifestyle / Business)
2. See filtered guild catalog → pick a guild → "Recruit & Go"
3. Redirected to Guild Hall with full roster installed
4. Quest board pre-populated, other banner-relevant templates browsable

### Returning User
1. Land on Lodge (dashboard)
2. Banner already set, everything filtered
3. Navigate freely

## 6. Implementation Notes

### Migrations
- One migration: `settings` table with `id`, `banner` (string, default nil), timestamps. Single row.

### No Content Schema Changes
- MDEx rendering is view-layer only. Existing `description`, `system_prompt`, `charter_text` fields remain strings.
- Banner tags live on compile-time structs (templates, archetypes, books), not in DB.

### Dependencies
- Add `mdex` to `mix.exs`
- Optional plugins: `mdex_mermaid`, `mdex_katex` (if math rendering desired)
- `use MDEx` in relevant LiveView modules for `~MD` sigil access
