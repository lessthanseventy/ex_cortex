# Nextcloud Integration Design

**Date:** 2026-03-12
**Scope:** Full Nextcloud integration — source, tools, output sink, docker infrastructure

## Overview

Add Nextcloud to ExCalibur's docker-compose stack as a self-contained collaboration platform that agents can read from, write to, and react to. Phased build covering infrastructure, event-driven source watching, agent tools, source blueprints, and output sinks.

## 1. Infrastructure — Docker Services

Add two new services to `docker-compose.yml`:

- **nextcloud** — `nextcloud:latest` on port 8080, persistent data volume, depends on nextcloud-db
- **nextcloud-db** — `mariadb:11`, isolated from ExCalibur's TimescaleDB

**Configuration:**
- `NEXTCLOUD_URL` env var (defaults to `http://nextcloud:80` in docker, `http://localhost:8080` outside)
- `NEXTCLOUD_USER` / `NEXTCLOUD_PASSWORD` env vars (app password auth)
- Init script (`docker/init-nextcloud.sh`): enables Flow, Notes, Calendar, Talk apps; creates default "ExCalibur" folder; registers Flow webhook rule

## 2. Nextcloud Client Module

`ExCalibur.Nextcloud.Client` — thin Req wrapper with auth + base URL:

- **WebDAV**: `propfind/1`, `get_file/1`, `put_file/2`, `mkcol/1`, `delete/1`
- **OCS REST**: `get/1`, `post/2` for Notes, Calendar, Talk, Activity APIs
- Auth: Basic auth with app password
- Configurable via `ExCalibur.Settings` (UI-changeable) and env vars

## 3. Source: Nextcloud Watcher

New source type `"nextcloud"` with dual mechanism:

### Event-driven (files)
Nextcloud Flow fires webhook on file create/update/delete → existing `WebhookController` → routes to linked quests/steps/evaluator. No new controller code needed.

### Activity API poller (Talk/Calendar/Notes)
New `ExCalibur.Sources.NextcloudWatcher` implementing `Sources.Behaviour`:
- Polls `/ocs/v2.php/apps/activity/api/v2/activity` with `since` parameter
- Filters by activity type (files, calendar, talk, notes)
- Configurable interval (default 30s)
- State: `%{last_activity_id: integer}`

## 4. Agent Tools

Seven new tools across three tiers:

### Safe tier
| Tool | API | Purpose |
|------|-----|---------|
| `search_nextcloud` | WebDAV PROPFIND | Search/list files by path/pattern |
| `read_nextcloud` | WebDAV GET | Read file content from Nextcloud |
| `read_nextcloud_notes` | Notes OCS API | Read/search Nextcloud Notes |

### Write tier
| Tool | API | Purpose |
|------|-----|---------|
| `write_nextcloud` | WebDAV PUT | Upload/create files |
| `create_nextcloud_note` | Notes OCS API | Create a note |
| `nextcloud_calendar` | CalDAV | Create/read calendar events |

### Dangerous tier
| Tool | API | Purpose |
|------|-----|---------|
| `nextcloud_talk` | Talk OCS API | Post messages to Talk channels |

## 5. Books (Source Blueprints)

Four new books in `book.ex`:

- **Nextcloud File Watcher** — Watch folder via Flow webhook, suggested guild varies
- **Nextcloud Talk Source** — Feed Talk messages into evaluation
- **Nextcloud Calendar Source** — Upcoming events as agent context
- **Nextcloud Notes Source** — Watch notes via Activity API

## 6. Output Sink

`ExCalibur.Nextcloud.Sink` — called from quest completion and lodge card creation:

- Writes quest outcomes to `ExCalibur/quests/<quest-name>/<date>.md` via WebDAV PUT
- Optionally posts summaries to a configured Talk channel
- Configurable per-quest via step config (`"output_to_nextcloud": true`)
- Creates directory structure automatically via MKCOL

## Approach: Hybrid Event Model

- **Primary:** Nextcloud Flow webhooks for file events (truly event-driven, reuses existing webhook infra)
- **Supplement:** Activity API polling for Talk/Calendar/Notes events that Flow doesn't cover
- This gives real-time where it matters most and full coverage everywhere else

## Phasing

1. **Phase 1:** Docker infrastructure + Client module + Settings UI
2. **Phase 2:** NextcloudWatcher source + Books
3. **Phase 3:** Safe tools (search, read files, read notes)
4. **Phase 4:** Write tools (write files, create notes, calendar)
5. **Phase 5:** Dangerous tools (Talk) + Output sink
