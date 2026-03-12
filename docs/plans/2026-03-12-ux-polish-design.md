# UX Polish: Navigation, Empty States, Cross-links, Context Lines

## Overview

Make ExCalibur's UI feel more connected and discoverable. Four areas of work:
nav improvements, standardized headers/empty states, cross-page contextual links,
and page-level context summaries.

## 1. Nav Improvements

### Reorder to match workflow

```
Town Square → Guild Hall → Quests → Library → Lodge → Grimoire → Settings
```

### Tooltips

Add `title` attribute to each nav link:

| Nav Item | Tooltip |
|----------|---------|
| Town Square | Choose your guild and banner |
| Guild Hall | Manage members, roles, and charters |
| Quests | Build workflows and set triggers |
| Library | Sources, scrolls, books, and dictionaries |
| Lodge | Bulletin board — notes, alerts, quest output |
| Grimoire | Quest history and accumulated lore |
| Settings | Tool and integration configuration |

### Activity dots

Small colored dot on Lodge and Grimoire nav items when there's been activity
since the user last visited that page. Tracked via session assigns
(`last_visited_lodge` / `last_visited_grimoire` timestamps compared against
latest card/run timestamps).

Green dot = new activity. No dot = caught up.

Implementation: Store last-visited timestamps in the socket assigns (per
LiveView mount). Track latest activity timestamps via PubSub — the root layout
needs access to these, so use a shared hook or on_mount callback that subscribes
to `lodge` and `quest_runs` topics.

## 2. Standardized Headers & Empty States

### Headers

Settings page is the only outlier — uses `text-2xl` with no tagline. Bring it
in line: `text-3xl font-bold tracking-tight` + tagline paragraph
("Configure tool integrations and external service connections.").

### Empty States

Upgrade dead ends to contextual guidance with links to prerequisite pages.

| Page | Current | Proposed |
|------|---------|----------|
| Lodge (no cards) | "No cards yet. Add one above or run a quest..." | "No cards yet. Cards appear here when quests run, or you can create one above. Set up quests from the **Quests** page." |
| Grimoire (no quests) | "No quests yet. Create one from the Quests page." | Keep + add: "Once quests run, their history and lore entries show up here." |
| Grimoire (no runs) | "No runs yet." | "No runs yet. Run this quest from the **Quests** page, or set a trigger to run it automatically." |
| Grimoire (no lore) | "No lore entries yet." | "No lore entries yet. Lore is written by quest steps as they process input." |
| Quests (no quests) | "No quests yet." | "No quests yet. Install one from the Quest Board above, or create your own." |
| Library (no sources) | "No active sources. Browse below to add some." | Keep as-is — already actionable. |

## 3. Cross-Page Contextual Links

Subtle wayfinding links (`text-sm text-muted-foreground`) connecting related
entities across pages. Not primary actions — just signposts.

### Guild Hall → Quests

Each member card shows which quests reference that member. Small text:
"Used in: Morning Briefing, Intake Loop" with links to `/quests`.

Query: find quests whose steps reference this member's name/id.

### Quests → Sources

Source-triggered quests show which source triggers them with a link to `/library`.
"Triggered by: Tech News Feed"

### Quests → Members

Quest step detail shows which member runs that step, linked to `/guild-hall`.

### Library → Quests

Active sources show which quest they feed. "Triggers: Morning Briefing"

### Grimoire → source context

Lore entries show which quest/step produced them (data likely already available
in the lore entry schema).

## 4. Page-Level Context Summaries

Dynamic status line under each page header. `text-sm text-muted-foreground`,
right below the tagline. Computed from data already loaded in mount.

| Page | Format |
|------|--------|
| Lodge | "{guild} · {n} cards · {n} pinned" |
| Guild Hall | "{guild} · {n} members · {n} active" |
| Quests | "{n} quests · {n} scheduled · {n} source-triggered" |
| Library | "{n} sources active · {n} books installed · {n} dictionaries" |
| Grimoire | "{n} quests tracked · {n} runs total · {n} lore entries" |
| Town Square | "Current guild: {name} · Banner: {banner}" (if set) |
| Settings | Skip — would be noisy |

## 5. What This Does NOT Change

- No new pages or routes
- No changes to data models or schemas
- No changes to guild terminology or page names
- Fantasy vocabulary stays as-is — tooltips bridge the gap
- No mobile-specific work (existing responsive layout is fine)
