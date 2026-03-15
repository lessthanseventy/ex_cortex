# Library & Stacks Implementation Plan

**Context:** Replace the current `/sources` page with two themed pages:
- `/library` — Browse and install pre-configured source "books" (source templates)
- `/stacks` — Manage active/installed sources (pause, resume, delete, status)

Books are standalone source blueprints — not tied to specific guilds. When installing a guild, relevant books are auto-installed. Users can also browse the Library independently and attach any book to any guild.

---

## Task 1: Define Book catalogue module

**File:** `lib/ex_cortex/sources/book.ex`

**Steps:**
1. Create a module that defines all available source books as data:
   ```elixir
   defmodule ExCortex.Sources.Book do
     defstruct [:id, :name, :description, :source_type, :default_config, :suggested_guild]

     @books [
       # Git books
       %__MODULE__{
         id: "git_repo_watcher",
         name: "Git Repo Watcher",
         description: "Watch a local git repository for new commits and generate diffs for review.",
         source_type: "git",
         default_config: %{"repo_path" => "", "branch" => "main", "interval" => 60_000},
         suggested_guild: "Code Review"
       },
       # Directory books
       %__MODULE__{
         id: "directory_watcher",
         name: "Directory Watcher",
         description: "Monitor a directory for new or changed files.",
         source_type: "directory",
         default_config: %{"path" => "", "patterns" => ["*.txt", "*.md"], "interval" => 30_000},
         suggested_guild: "Content Moderation"
       },
       # Feed books
       %__MODULE__{
         id: "rss_feed",
         name: "RSS/Atom Feed",
         description: "Poll an RSS or Atom feed for new entries.",
         source_type: "feed",
         default_config: %{"url" => "", "interval" => 300_000},
         suggested_guild: "Risk Assessment"
       },
       # Webhook books
       %__MODULE__{
         id: "webhook_receiver",
         name: "Webhook Receiver",
         description: "Expose a POST endpoint that accepts data pushes. Supports optional Bearer token auth.",
         source_type: "webhook",
         default_config: %{},
         suggested_guild: nil
       },
       # URL books
       %__MODULE__{
         id: "url_watcher",
         name: "URL Watcher",
         description: "Periodically fetch a URL and detect content changes.",
         source_type: "url",
         default_config: %{"url" => "", "interval" => 60_000},
         suggested_guild: nil
       },
       # WebSocket books
       %__MODULE__{
         id: "websocket_stream",
         name: "WebSocket Stream",
         description: "Connect to a WebSocket endpoint and process incoming messages.",
         source_type: "websocket",
         default_config: %{"url" => "", "message_path" => "", "interval" => 60_000},
         suggested_guild: nil
       }
     ]

     def all, do: @books
     def get(id), do: Enum.find(@books, &(&1.id == id))
     def for_guild(guild_name), do: Enum.filter(@books, &(&1.suggested_guild == guild_name))
   end
   ```

**Verify:** `mix compile --warnings-as-errors`

---

## Task 2: Create Library LiveView page

**Files:**
- `lib/ex_cortex_web/live/library_live.ex` (new)
- `test/ex_cortex_web/live/library_live_test.exs` (new)

**Steps:**
1. Create LibraryLive that displays all available books as cards in a grid:
   - Each card shows: book name, description, source type badge, suggested guild (if any)
   - "Add to Guild" button that expands a guild picker dropdown
   - On add: creates a Source from the book's defaults with `status: "paused"`, redirects to `/stacks`
   - If no guilds installed: show message directing to Guild Hall
2. Route: `live "/library", LibraryLive, :index`
3. Test: assert page renders with book names

**Verify:** `mix compile --warnings-as-errors && mix test`

---

## Task 3: Rename SourcesLive to StacksLive

**Files:**
- `lib/ex_cortex_web/live/stacks_live.ex` (rename from sources_live.ex)
- `test/ex_cortex_web/live/stacks_live_test.exs` (rename from sources_live_test.exs)

**Steps:**
1. Rename `SourcesLive` module to `StacksLive`
2. Update page title from "Sources" to "Stacks"
3. Remove the "Add Source" form (that's now the Library's job)
4. Keep: source list with pause/resume/delete, status badges, webhook URL display, error display
5. Add empty state: "Your stacks are empty. Browse the Library to add books."
6. Update route: `live "/stacks", StacksLive, :index`
7. Delete old `sources_live.ex` and `sources_live_test.exs`
8. Update test module name and route

**Verify:** `mix compile --warnings-as-errors && mix test`

---

## Task 4: Update nav, routes, and redirects

**Files:**
- `lib/ex_cortex_web/components/layouts/root.html.heex`
- `lib/ex_cortex_web/router.ex`
- `lib/ex_cortex_web/live/guild_hall_live.ex`

**Steps:**
1. Nav links: replace "Sources" with "Library" and "Stacks" (between Quests and Evaluate)
2. Router: remove `/sources` route, add `/library` and `/stacks`
3. Guild Hall: change `@post_install_redirect` from `"/sources"` to `"/stacks"`
4. Guild Hall: update `create_default_source` to use Book module instead of hardcoded defaults
5. Update empty state links that reference `/sources` or Guild Hall

**Verify:** `mix compile --warnings-as-errors && mix test`

---

## Task 5: Update CLAUDE.md and final verification

**Steps:**
1. Update CLAUDE.md:
   - Add Library and Stacks to pages list
   - Add Book concept to terminology map (Sources → Books in Library, active sources in Stacks)
   - Remove `/sources` reference
2. Run `mix format`
3. Run `mix compile --warnings-as-errors`
4. Run `mix test`

**Verify:** All pass cleanly.
