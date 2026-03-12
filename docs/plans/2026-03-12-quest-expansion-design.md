# Quest Expansion & Lodge Dashboard Design

## Overview

Add 15 new quests to Everyday Council leveraging the expanded 29-tool catalog, upgrade
the lodge from a text-blob feed to a typed card dashboard, and wire dangerous tool calls
through a proposal queue for human approval.

## 1. New Quest Catalog (15 quests)

### A. Personal Life OS Expansion (Everyday Council)

| Quest | Trigger | Roster | Output | Loop Tools |
|-------|---------|--------|--------|------------|
| Email Triage | scheduled 0 7 * * * | news-correspondent | lodge_card (pinned, briefing) | query_lore, search_email, read_email |
| Email Cleanup | scheduled 0 22 * * 0 | scope-realist | lodge_card (action_list) | query_lore, search_email, read_email |
| GitHub Pulse | scheduled 0 8 * * * | evidence-collector | lodge_card (pinned, table) | query_lore, search_github, read_github_issue, list_github_notifications |
| GitHub Weekly | scheduled 0 9 * * 1 | the-historian | lodge_card (briefing) | query_lore, search_github, read_github_issue |
| Research Agent | manual | evidence-collector + challenger | artifact + lodge_card (freeform) | query_lore, web_search, web_fetch, search_obsidian, read_obsidian, search_email, read_pdf |
| Weekly Life Synthesis | scheduled 0 19 * * 0 | the-historian + life-coach | lodge_card (briefing) | query_lore, search_obsidian, read_obsidian, search_email, search_github |

### B. Multi-Modal Intake

| Quest | Trigger | Roster | Output | Loop Tools |
|-------|---------|--------|--------|------------|
| Smart Intake | source | journal-keeper (write) | artifact | query_lore, search_obsidian, web_search, web_fetch, read_pdf, describe_image, read_image_text, download_media, extract_frames, analyze_video, create_obsidian_note |
| PDF Deep Read | manual | journal-keeper (write) | artifact + lodge_card (briefing) | read_pdf, query_lore, web_search, create_obsidian_note |
| Image Analysis | manual | journal-keeper | artifact | describe_image, read_image_text, query_lore |
| Video Breakdown | manual | journal-keeper (write) | artifact + lodge_card (media) | download_media, extract_frames, analyze_video, extract_audio, create_obsidian_note, query_lore |

### C. Cross-Guild Intelligence

| Quest | Trigger | Roster | Output | Loop Tools |
|-------|---------|--------|--------|------------|
| Morning Command Brief | scheduled 0 7 * * * | life-coach | lodge_card (pinned, briefing) multi-card | query_lore, search_email, search_github, list_github_notifications, web_search, search_obsidian |
| Trend Detector | scheduled 0 10 * * * | the-historian | lodge_card (metric) | query_lore, web_search, search_obsidian |
| Obsidian Librarian | scheduled 0 3 * * * | journal-keeper (write) | lodge_card (checklist) | search_obsidian, search_obsidian_content, read_obsidian, read_obsidian_frontmatter, create_obsidian_note, daily_obsidian |

### D. Proactive Automation

| Quest | Trigger | Roster | Output | Loop Tools |
|-------|---------|--------|--------|------------|
| Issue Drafter | manual | evidence-collector | proposal | search_github, read_github_issue, query_lore, create_github_issue |
| Email Responder | manual | news-correspondent | proposal | read_email, search_email, query_lore, web_search, send_email |

### Smart Intake — Content-Type Detection

Smart Intake replaces Journal Intake. When source items arrive, the LLM detects type
and routes to appropriate tools:

| Content Signal | Detection | Tools Used |
|----------------|-----------|------------|
| URL to article/page | starts with http, not file/video | web_fetch |
| URL to video | youtube.com, vimeo, etc. | download_media, extract_frames, analyze_video |
| PDF path | ends in .pdf | read_pdf |
| Image path | ends in .jpg/.png/.webp | describe_image, read_image_text |
| Email message ID | thread: or msg: prefix | read_email |
| Plain text/thought | everything else | process as-is |

After extraction: summarize, tag, cross-reference with lore and Obsidian, write artifact,
optionally create Obsidian note.

## 2. Lodge Card System — Typed Dashboard

### Card Types (7 types)

| Type | Rendering | Example |
|------|-----------|---------|
| briefing | Markdown prose with sections | Morning Command Brief, Email Triage |
| checklist | Interactive checkboxes that persist | Priority Reset, Obsidian Librarian |
| action_list | Rows with approve/reject per item, custom button labels | Email Cleanup, Proposal queue |
| table | Structured rows/columns, read-only | GitHub Pulse (PRs, issues) |
| media | Image/thumbnail + caption | Image Analysis, Video Breakdown |
| metric | Big number + trend indicator | Trend Detector |
| freeform | Raw markdown, inline-editable | Research Agent results |

### action_list Metadata Format

```json
{
  "items": [
    {"id": "1", "label": "Marketing Weekly from Substack", "detail": "Last opened: never", "status": "pending"},
    {"id": "2", "label": "GitHub Security Alerts", "detail": "Last opened: 2 days ago", "status": "pending"}
  ],
  "action_labels": {"approve": "Unsubscribe", "reject": "Keep"}
}
```

### Pinning & Ownership

- Quests declare `pin: true` and `pin_slug: "email-triage"` to overwrite the same card
  on each run instead of creating new ones.
- Pinned cards stick to the top in a responsive grid (3 col desktop, 2 tablet, 1 mobile).
- Cards self-size by type: metric = compact (1/3 width), briefing/table = 2/3 or full,
  action_list = always full width.
- Pin order controlled by `pin_order` integer.
- Unpinned cards flow chronologically below in a collapsible feed.

### Multi-Card Ownership

A quest can produce multiple cards with different pin_slugs. Example: Morning Command
Brief produces separate email highlights (briefing), GitHub activity (table), and
today's priorities (checklist) cards. Declared in quest definition:

```
cards: [
  %{"pin_slug" => "command-brief-email", "card_type" => "briefing", "pinned" => true},
  %{"pin_slug" => "command-brief-github", "card_type" => "table", "pinned" => true},
  %{"pin_slug" => "command-brief-agenda", "card_type" => "checklist", "pinned" => true}
]
```

### Card Interactivity

- Checklist: phx-click toggles items, persists to metadata.
- Action list: approve/reject per item, batch approve all / reject all.
- Freeform: click to edit markdown body, saves back.
- Card actions menu (top-right, every card): Dismiss, Pin/Unpin, Re-run quest,
  View quest, View history (pinned cards only).

### Visual Identity

- Guild banner determines accent color: tech = blue, lifestyle = green, business = amber.
- Card type determines icon: briefing = scroll, checklist = checkbox,
  action_list = gavel, table = grid, media = image, metric = chart, freeform = pen.
- Title bar: icon + title + guild badge + timestamp + actions menu.

### Card Lifecycle

- Pinned cards: live forever, overwritten in place. Previous versions saved to
  lodge_card_versions table.
- Unpinned cards: auto-archive after configurable days (default 30).
- Status: active, archived, dismissed.
- Dismissed cards hidden from default view, visible in Archive tab.

## 3. Proposal Queue for Dangerous Actions

### Flow

1. Quest runs, LLM calls a dangerous tool (send_email, create_github_issue, etc.)
2. Step runner intercepts: creates a Proposal record instead of executing
3. Returns `{:ok, "Action queued for approval"}` to the LLM
4. Pinned action_list card on lodge shows pending proposals
5. User approves or rejects each one
6. On approve: system executes the tool call with saved arguments
7. On reject: proposal marked rejected, nothing happens

### Proposal Record

Extends existing proposals table:

| Column | Type | Purpose |
|--------|------|---------|
| tool_name | string | "send_email", "create_github_issue", etc. |
| tool_args | jsonb | Exact arguments the LLM passed |
| context | text | Why the quest wants to do this |
| status | string | pending, approved, rejected, executed, failed |
| result | text (nullable) | What happened after execution |

### Which Tools

Only `@dangerous` tier goes through proposals: send_email, create_github_issue,
comment_github, run_quest. Everything in `@safe` and `@write` executes immediately.

## 4. Data Model Changes

### lodge_cards — new columns

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| card_type | string | "briefing" | Type key for rendering |
| pin_slug | string (unique, nullable) | nil | Upsert key for pinned cards |
| pinned | boolean | false | Sticks to top of lodge |
| pin_order | integer | 0 | Sort order within pinned zone |
| metadata | jsonb | %{} | Type-specific structured data |
| quest_id | integer (nullable) | nil | Which quest owns this card |
| guild_name | string (nullable) | nil | Visual identity |
| status | string | "active" | active, archived, dismissed |

### lodge_card_versions — new table

| Column | Type | Purpose |
|--------|------|---------|
| card_id | references lodge_cards | Which card |
| body | text | Previous body |
| metadata | jsonb | Previous metadata |
| replaced_at | utc_datetime | When it was replaced |

### proposals — new columns

| Column | Type | Purpose |
|--------|------|---------|
| tool_name | string | Tool that was called |
| tool_args | jsonb | Saved arguments |
| context | text | LLM explanation |
| result | text (nullable) | Execution result |

Status values: pending, approved, rejected, executed, failed.

## 5. Updated Campaigns

| Campaign | Trigger | Steps |
|----------|---------|-------|
| Intake Loop | source | Smart Intake (replaces Journal Intake) |
| Morning Start | scheduled 0 7 * * * | Email Triage → Morning Command Brief → Daily Check-in |
| Midday Check | scheduled 0 12 * * * | GitHub Pulse → Midday Pulse |
| Evening Close | scheduled 0 21 * * * | Evening Wrap |
| Weekly Close | scheduled 0 19 * * 5 | Weekly News Digest → GitHub Weekly → Weekly Life Synthesis → Weekly Reflection |
| Monthly Close | scheduled 0 10 1 * * | Monthly Review |
| Nightly Maintenance | scheduled 0 3 * * * | Obsidian Librarian → Trend Detector |
| Weekly Cleanup | scheduled 0 22 * * 0 | Email Cleanup |

## 6. Step Runner Changes

### Dangerous tool interception

When executing a tool call:
1. Check if the tool is in `@dangerous`
2. If yes: create Proposal, return `{:ok, "Action queued for approval"}`
3. If no: execute normally

### Multi-card output

When a quest declares `cards` in its definition, the step runner creates/updates
lodge cards per the card spec instead of producing a single lodge_card output.

## 7. What Does NOT Change

- Postgres remains the operational store
- Existing quest/step/campaign schemas unchanged
- Member rank/model progression unchanged
- Source types and source worker architecture unchanged
- Obsidian sync layer unchanged (fire-and-forget side effect)
- The 29 tools themselves are unchanged
