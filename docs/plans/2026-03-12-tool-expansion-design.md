# Tool Expansion & Obsidian Knowledge Layer Design

## Overview

Expand ExCalibur's tool calling layer from 3 tools to 29, introduce Obsidian as a
durable knowledge layer synced from Postgres, add a settings UI for tool config,
and wire every guild to appropriate tools by role and purpose.

## 1. Safety Tiers

Three tiers replace the current two ("safe" / "yolo"):

| Tier | Scope | Examples |
|------|-------|---------|
| **safe** | Read-only, no side effects | `query_lore`, `search_obsidian`, `read_email`, `search_github`, `read_pdf`, `describe_image`, `web_fetch`, `web_search` |
| **write** | Modify local state | `create_obsidian_note`, `write_obsidian`, `daily_obsidian`, `jq_transform`, `extract_audio`, `extract_frames`, `download_media` |
| **dangerous** | External side effects | `send_email`, `create_github_issue`, `comment_github`, `run_quest` |

Members specify tier in config: `"tools" => "all_safe"` (default),
`"tools" => "write"`, `"tools" => "dangerous"`, or a specific list of tool names.

Registry changes:
```elixir
@safe [QueryLore, SearchObsidian, ReadObsidian, ...]
@write [CreateObsidianNote, DailyObsidian, DownloadMedia, ...]
@dangerous [SendEmail, CreateGithubIssue, RunQuest, ...]

def resolve_tools(:all_safe), do: Enum.map(@safe, & &1.tool())
def resolve_tools(:write), do: Enum.map(@safe ++ @write, & &1.tool())
def resolve_tools(:dangerous), do: Enum.map(@safe ++ @write ++ @dangerous, & &1.tool())
```

## 2. Tool Catalog (29 tools)

### Knowledge Management (Obsidian) — via obsidian-cli

| Tool | Tier | Description |
|------|------|-------------|
| `search_obsidian` | safe | Fuzzy search note titles |
| `search_obsidian_content` | safe | Full-text search note bodies |
| `read_obsidian` | safe | Print a note's contents |
| `read_obsidian_frontmatter` | safe | Read note frontmatter/metadata |
| `create_obsidian_note` | write | Create note with title, body, optional frontmatter |
| `daily_obsidian` | write | Create/append to today's daily note |

### Email (isync + notmuch + msmtp)

| Tool | Tier | Description |
|------|------|-------------|
| `search_email` | safe | Search mailbox via notmuch |
| `read_email` | safe | Read specific message |
| `send_email` | dangerous | Compose and send via msmtp |

### GitHub (gh CLI)

| Tool | Tier | Description |
|------|------|-------------|
| `search_github` | safe | Search issues/PRs/repos |
| `read_github_issue` | safe | Read issue/PR details |
| `list_github_notifications` | safe | List notifications |
| `create_github_issue` | dangerous | Create issue |
| `comment_github` | dangerous | Comment on issue/PR |

### Data Processing

| Tool | Tier | Description |
|------|------|-------------|
| `jq_query` | safe | Run jq expression against JSON |
| `read_pdf` | safe | Extract text via pdftotext |
| `convert_document` | safe | Convert formats via pandoc |

### Web

| Tool | Tier | Description |
|------|------|-------------|
| `web_fetch` | safe | Fetch URL, extract readable content via w3m/pandoc |
| `web_search` | safe | DuckDuckGo search via ddgr --json |

### Media & Vision

| Tool | Tier | Description |
|------|------|-------------|
| `describe_image` | safe | Send image to vision model, get description |
| `read_image_text` | safe | OCR/text extraction from images |
| `download_media` | write | yt-dlp to pull video/audio from URL |
| `extract_audio` | write | ffmpeg to extract audio track |
| `transcribe_audio` | safe | Speech-to-text (whisper via Ollama or API) |
| `extract_frames` | write | ffmpeg keyframe or interval extraction |
| `analyze_video` | safe | Composite: extract frames + describe each → timeline |

### Existing (reclassified)

| Tool | Tier | Change |
|------|------|--------|
| `query_lore` | safe | No change |
| `fetch_url` | safe | Promoted from yolo |
| `run_quest` | dangerous | Promoted from safe |

### Implementation Pattern

Every tool follows the same pattern:

```elixir
defmodule ExCalibur.Tools.SearchObsidian do
  @tier :safe

  def tool do
    ReqLLM.Tool.new!(
      name: "search_obsidian",
      description: "Fuzzy search Obsidian vault note titles.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "Search query"}
        },
        "required" => ["query"]
      },
      callback: &call/1
    )
  end

  def call(%{"query" => query}) do
    vault = ExCalibur.Settings.get(:obsidian_vault)
    args = ["search", query, "--print"] ++ if(vault, do: ["--vault", vault], else: [])
    case System.cmd("obsidian-cli", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end
end
```

## 3. Obsidian Knowledge Layer

Obsidian becomes the durable knowledge store. Postgres remains the operational
layer for fast UI queries. Every lore entry and lodge card is synced to Obsidian
as a markdown file.

### Vault Structure

```
<Vault>/
  ExCalibur/
    Lore/
      2026-03-12-big-ten-tampering.md
      2026-03-12-morning-briefing.md
    Lodge/
      morning-briefing-card.md
      midday-pulse-card.md
    Quests/
      intake-loop-2026-03-12.md
```

### Frontmatter Convention

```yaml
---
type: lore_entry
source: step
quest_id: 8
tags: [sports, NCAA]
importance: 4
pinned: false
status: active
card_type: briefing
created: 2026-03-12T03:06:39Z
updated: 2026-03-12T03:06:39Z
---
```

Dataview queries in Obsidian can then do:
```dataview
TABLE tags, importance, created
FROM "ExCalibur/Lore"
WHERE importance >= 4
SORT created DESC
```

### Sync Mechanics

- `ExCalibur.Obsidian.Sync` module with `sync_lore_entry/1` and `sync_lodge_card/1`
- Called as side effect after every DB write in `Lore.write_artifact/2`,
  `Lodge.post_card/1`, etc.
- New notes: `obsidian-cli create` or `File.write/2` to vault path
- Updates: `File.write/2` to known slug path (obsidian-cli lacks update command)
- Slug: `"Morning Briefing — 2026-03-12"` → `morning-briefing-2026-03-12.md`
- Pinned lodge cards: quest always writes to same slug, replacing body,
  preserving pinned frontmatter

### What Does NOT Change

- Postgres remains the operational store
- LiveView reads from Postgres
- Obsidian is sync target + tool-accessible knowledge layer
- Deleting a note in Obsidian does not auto-delete from Postgres

## 4. Media Pipeline

### Directory Structure

All downloaded/extracted media goes to a configurable temp dir
(default `/tmp/ex_calibur/media/`). Each job gets a UUID subdirectory.

### Video Analysis Flow

```
URL → download_media (yt-dlp) → <uuid>/video.mp4
  ├→ extract_audio (ffmpeg) → audio.wav → transcribe_audio → text
  └→ extract_frames (ffmpeg) → frame_001.jpg, frame_002.jpg, ...
       └→ describe_image (vision model) per frame → timeline
```

`analyze_video` is a composite tool that orchestrates internally.
The LLM calls it once and gets back transcript + visual timeline.

### Frame Extraction Modes

- **keyframes** (default): `-vf "select=eq(ptype\\,I)"` — fast
- **interval**: `-vf fps=1/N` — one frame every N seconds, better for lectures

### Vision Model Routing

`describe_image` and `read_image_text` check config for provider:
- `vision_provider: "ollama"` → use configured ollama vision model
- `vision_provider: "claude"` → use Claude API with image content
- Falls back to other provider if primary unavailable
- Errors if neither configured

## 5. Guild Tool Wiring

### Tech Guilds

| Guild | Member Tier | Key New Tools | loop_tools |
|-------|------------|---------------|------------|
| Code Review | write | search_github, read_github_issue, jq_query, web_search | query_lore, search_github, search_obsidian |
| Accessibility Review | safe | web_search, web_fetch, read_pdf | query_lore, web_search |
| Dependency Audit | safe | search_github, read_github_issue, web_search | query_lore, web_search, search_github |
| Incident Triage | write | search_github, search_email, read_email, web_search | query_lore, search_github, search_email |
| Performance Audit | safe | search_github, jq_query, web_search | query_lore, search_github |
| Quality Collective | safe | web_search, web_fetch, read_pdf | query_lore, web_search |
| Platform Guild | safe | search_github, jq_query, web_search | query_lore, search_github |
| The Skeptics | safe | web_search, web_fetch, search_obsidian | query_lore, web_search, search_obsidian |

### Business Guilds

| Guild | Member Tier | Key New Tools | loop_tools |
|-------|------------|---------------|------------|
| Contract Review | safe | read_pdf, search_obsidian, search_email, web_search | query_lore, search_obsidian, search_email |
| Risk Assessment | safe | web_search, jq_query, search_github | query_lore, web_search |
| Product Intelligence | safe | web_search, search_github, search_email | query_lore, web_search, search_email |
| Market Signals | safe | web_search, web_fetch | query_lore, web_search |

### Lifestyle Guilds

| Guild | Member Tier | Key New Tools | loop_tools |
|-------|------------|---------------|------------|
| Everyday Council | write (journal-keeper), safe (others) | Per-member — see below | query_lore, search_obsidian, web_search |
| Tech Dispatch | safe | web_search, web_fetch, search_obsidian | query_lore, web_search |
| Sports Corner | safe | web_search, web_fetch, describe_image | query_lore, web_search |
| Culture Desk | safe | web_search, web_fetch, describe_image, analyze_video | query_lore, web_search |
| Science Watch | safe | web_search, web_fetch, read_pdf | query_lore, web_search |
| Creative Studio | safe | search_obsidian, read_obsidian, web_search | query_lore, search_obsidian |
| Content Moderation | safe | web_search, describe_image | query_lore, web_search |

### Everyday Council Per-Member Wiring

| Member | Tier | Tools | Rationale |
|--------|------|-------|-----------|
| Journal Keeper | write | create_obsidian_note, daily_obsidian, read_pdf, describe_image | Processes intake, writes to knowledge store |
| News Correspondent | safe | web_search, web_fetch, search_email, search_obsidian | Researches and enriches news context |
| Life Coach | safe | read_obsidian, search_obsidian, query_lore, search_email | Reads commitments, context, patterns |
| The Historian | safe | read_obsidian, search_obsidian, query_lore | Pattern recognition across knowledge |
| Evidence Collector | safe | web_search, web_fetch, read_pdf, search_github | Gathers supporting evidence |
| Scope Realist | safe | query_lore, search_obsidian | Project context and priorities |
| Risk Assessor | safe | query_lore, web_search | Risk signals |
| The Optimist | safe | query_lore | Minimal tooling, stays grounded |
| Challenger | safe | query_lore, web_search | Counterarguments |

## 6. New Source Types

The tool layer enables three new source types:

### ObsidianWatcher

Polls `obsidian-cli list` on a watched folder, diffs against last known state,
triggers quests when notes are created or modified. Enables the Journal Keeper to
auto-ingest Obsidian daily notes.

### EmailSource

Runs `notmuch new && notmuch search --output=messages tag:new`, ingests new
messages as source items. Replaces the Everyday Council "Personal Inbox Webhook"
with a real email inbox source.

### MediaSource

Uses `yt-dlp --flat-playlist` to monitor a YouTube channel/playlist for new
uploads. New video → download → transcribe → feed into intake quest.

## 7. Settings UI

New `/settings` page with config sections stored in a `config` jsonb column on
the existing `settings` table.

| Section | Config Keys |
|---------|------------|
| Obsidian | vault_name, sync_enabled, subfolder_prefix |
| Email | msmtp_account, notmuch_db_path, sync_interval |
| GitHub | default_org, default_repo |
| Vision | vision_provider (ollama/claude), ollama_vision_model, fallback_enabled |
| Media | media_dir, frame_mode (keyframes/interval), cleanup_ttl_hours |
| Web Search | ddgr_num_results, ddgr_region |
| Tools | Per-tool enable/disable toggles |

Read via `ExCalibur.Settings.get(:obsidian_vault)` etc.

## 8. System Dependencies

Already installed: jq, gh, neomutt, w3m, pandoc, pdftotext, ffmpeg, yt-dlp,
obsidian, obsidian-cli, imagemagick (convert/magick), ddgr.

Newly installed (need configuration): isync, notmuch.

Not yet installed (optional, for later): whisper-cpp or openai-whisper (Python)
for local transcription. Can use Ollama whisper model as alternative.

## 9. What This Does NOT Change

- Postgres remains the operational data store
- LiveView reads from Postgres for speed
- The existing ReqLLM.Tool struct format is unchanged
- The Claude agent loop in ExCalibur.LLM.Claude is unchanged
- Ollama still lacks native tool calling (falls back to plain completion)
- Member rank/model progression is unchanged
- Quest/campaign structure is unchanged
