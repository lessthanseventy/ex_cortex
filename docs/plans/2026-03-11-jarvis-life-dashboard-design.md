# Jarvis Life Dashboard — Design

## Goal

Make Everyday Council the one-click "give me Jarvis" button. One install gets a full life OS: all news feeds, auto-intake, three daily briefings, lodge card processing, weekly reflection, monthly review. Add Lodge as a first-class quest trigger.

## Architecture

### Lodge Trigger (new quest trigger type)

Add `"lodge"` to the quest trigger enum alongside manual/source/scheduled/once/lore.

**Schema changes:**
- `Quest` gets `lodge_trigger_types` (`{:array, :string}`, default `[]`) — card types to react to (e.g. `["todo", "checklist"]`). Empty = all.
- `Quest` gets `lodge_trigger_tags` (`{:array, :string}`, default `[]`) — tags to filter on. Empty = all.

**Runtime:**
- New `LodgeTriggerRunner` GenServer subscribes to `"lodge"` PubSub topic.
- On card create/update, matches active quests with `trigger: "lodge"` by type/tag overlap.
- Fires matching quests with card body as input.
- Mirrors the existing `LoreTriggerRunner` pattern.

**UI:**
- "Lodge" option in quest trigger dropdown.
- Type filter (multi-select or comma-separated) and tag filter inputs, same pattern as lore trigger tags.

### Everyday Council — Full Jarvis Template

**Sources (11 feeds + 1 webhook):**
- Personal Inbox Webhook
- Hacker News, The Verge, Ars Technica (tech)
- Reuters Business, Financial Times (business)
- ESPN, BBC Sport (sports)
- Pitchfork, AV Club (culture)
- Science Daily, Nature News (science)

**Steps (8):**

| Step | Trigger | Output | Description |
|------|---------|--------|-------------|
| Journal Intake | source (webhook) | lodge_card | Auto-categorize dropped content into typed lodge cards |
| Morning Briefing | scheduled 8am | lodge_card (note) | Overnight news synthesis + pending todos |
| Midday Pulse | scheduled 12pm | lodge_card (note) | Urgent items, todo progress, breaking news |
| Evening Debrief | scheduled 9pm | lodge_card (note) | Day summary, tomorrow preview |
| Todo Processor | lodge (type: todo) | artifact | Break todos into actionable sub-steps, log to grimoire |
| News Digest | source (feeds) | artifact | Synthesize feed items into tagged lore entries |
| Weekly Reflection | scheduled Mon 9am | lodge_card (augury) | Week in review — patterns, highlights, trends |
| Monthly Review | scheduled 1st 9am | lodge_card (augury) | Big picture patterns, priority check |

**Members auto-recruited (life_use):**
- The Life Coach, The Journal Keeper, The Correspondent, The Market Analyst, The Sports Anchor, The Science Desk

**Key decisions:**
- Briefings output to lodge_card so they land on the dashboard immediately.
- Journal intake auto-detects card type from content (links → link cards, bullet lists → checklists).
- News Digest tags entries by domain (tech, sports, business, culture, science) so weekly/monthly can pull the right context.
- Todo Processor uses the new lodge trigger — fires when a todo card appears.

### Individual Lifestyle Template Gating

Individual lifestyle templates (Tech Dispatch, Sports Corner, Market Signals, Culture Desk, Science Watch) get a new requirement: `{:not_installed, "everyday_council"}`.

When Everyday Council is active, these show as unavailable with "Included in Everyday Council".

Installing Everyday Council when an individual dispatch already exists works fine — `Board.install` skips sources/steps that already exist by name, and creates the rest.

## Tech Stack

- Elixir/Phoenix LiveView (existing)
- Ecto migrations for new quest fields
- PubSub for lodge trigger (existing "lodge" topic)
- GenServer for LodgeTriggerRunner (mirrors LoreTriggerRunner)
