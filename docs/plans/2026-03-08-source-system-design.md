# Source System Design

## Concept

A **Source** is a supervised process that feeds data into a guild for autonomous evaluation. Sources are generic — any source type can be attached to any guild. Each guild ships with a sensible default source, but users can mix and match.

## Source Types

| Type | Mechanism | Default For | Config |
|------|-----------|-------------|--------|
| **GitWatcher** | Polls repo for new commits/diffs | Code Review Guild | repo_path, branch, interval |
| **DirectoryWatcher** | Watches filesystem for new/changed files | Content Moderation Guild | path, patterns, interval |
| **FeedWatcher** | Fetches RSS/Atom feed | Risk Assessment Guild | url, interval |
| **WebhookReceiver** | Exposes POST endpoint | Any | auth_token, content_type |
| **UrlWatcher** | Fetches URL, diffs content | Any | url, interval, css_selector |
| **WebSocketSource** | Connects to WS endpoint | Any | url, message_path, reconnect_interval |

## Data Model

### `excellence_sources` table

```sql
id              uuid primary key
guild_name      varchar not null  -- which guild charter this feeds
source_type     varchar not null  -- "git", "directory", "feed", "webhook", "url", "websocket"
config          jsonb not null    -- type-specific configuration
state           jsonb default '{}' -- cursor, last_seen, etc.
status          varchar default 'active' -- active, paused, error
last_run_at     utc_datetime
error_message   varchar
inserted_at     utc_datetime
updated_at      utc_datetime
```

### `%SourceItem{}` (in-memory struct, not persisted)

```elixir
%SourceItem{
  source_id: uuid,
  guild_name: string,
  type: string,        # "commit", "file", "feed_entry", "webhook_payload", "url_diff", "ws_message"
  content: string,     # the actual content to evaluate
  metadata: map        # source-specific: commit SHA, filename, feed title, etc.
}
```

## Source Behaviour

```elixir
defmodule ExCortex.Sources.Behaviour do
  @callback init(config :: map()) :: {:ok, state :: map()}
  @callback fetch(state :: map(), config :: map()) :: {:ok, [SourceItem.t()], new_state :: map()} | {:error, term()}
  @callback stop(state :: map()) :: :ok
end
```

Poll-based sources (Git, Directory, Feed, Url) implement `fetch/2` called on interval.
Push-based sources (WebSocket) override the GenServer to maintain a persistent connection.
Webhook is a Phoenix controller, not a GenServer — DB row stores config only.

## Supervision

```
Application
  └── SourceSupervisor (DynamicSupervisor)
        ├── SourceWorker (GitWatcher, source_id: "abc")
        ├── SourceWorker (FeedWatcher, source_id: "def")
        └── SourceWorker (WebSocketSource, source_id: "ghi")
```

- On boot: query all `status: "active"` sources, start a worker for each
- `SourceWorker` is a GenServer that:
  1. Reads config from DB
  2. Calls `source_type.init(config)`
  3. Runs fetch loop on configured interval
  4. For each SourceItem, runs guild evaluation via existing pipeline
  5. Writes updated state back to DB
  6. On error: sets `status: "error"`, `error_message` in DB, crashes (supervisor restarts with backoff)

## Evaluation Pipeline

SourceItem → find guild's template module → build roles + actions from metadata → `Orchestrator.evaluate/4` → Decision persisted → Outcome tracked

Same path as the manual Evaluate page. The only difference is the input comes from a source instead of a textbox.

## Guild Hall Integration

When installing a guild:
1. Write ResourceDefinitions (existing behavior)
2. Prompt "Configure a source?" with default source type pre-selected
3. Source config form (type-specific fields)
4. On save: insert source row, SourceSupervisor starts the worker

## Sources UI

Add a `/sources` page (or tab on guild hall):
- List all sources with status, guild, type, last_run, error
- Pause/resume/delete controls
- "Add Source" button with type picker + config form
- Real-time status updates via PubSub

## Default Guild Pairings

### Code Review Guild + GitWatcher
- Config: local repo path (or git clone URL), branch (default: main), interval (default: 60s)
- Emits: commit diffs as SourceItems
- Metadata: commit SHA, author, message

### Content Moderation Guild + DirectoryWatcher
- Config: directory path, file patterns (default: ["*.txt", "*.md"]), interval (default: 30s)
- Emits: new/modified file contents as SourceItems
- Metadata: filename, size, modified_at

### Risk Assessment Guild + FeedWatcher
- Config: RSS/Atom URL, interval (default: 300s)
- Emits: new feed entries (title + description + content) as SourceItems
- Metadata: feed title, published_at, link

## What Stays Internal

- Source types are Elixir modules in `lib/ex_cortex/sources/`
- SourceItem is an in-memory struct, not persisted (Decisions capture the result)
- Source state (cursors, last_seen) persisted in the sources table jsonb column
- Webhook auth is simple bearer token comparison

## Future (not in scope)

- Source marketplace (community source types)
- Source chaining (output of one source feeds another)
- Filtering/transformation rules per source
- Rate limiting per source
