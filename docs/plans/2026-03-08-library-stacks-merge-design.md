# Library + Stacks Merge Design

**Date:** 2026-03-08
**Status:** Approved, ready to implement

## Problem

- `/library` and `/stacks` are separate pages with no cross-awareness
- When a guild is installed, pre-configured sources appear in Stacks but the user has no way to discover them from Library
- Browsing the library gives no indication of what's already installed
- The two-page split adds friction for a workflow that is naturally unified: "what sources do I have, what else can I add?"

## Decision

Merge Library and Stacks into a single `/library` page. Remove `/stacks` from the nav.

Custom sources (no `book_id`) are a non-issue — no UI exists to create them outside the library flow.

---

## Page Structure

### Active Sources (top section, always visible)

A compact list of everything currently in the user's stacks. Shows immediately after guild install, answering the "where are my pre-configured sources?" confusion.

Columns: name, source type badge, status (color-coded), action buttons.

- **Active** — green indicator, Pause + Delete buttons
- **Paused** — amber indicator, Resume + Delete buttons
- **Error** — red indicator, error message inline, Resume + Delete buttons
- **Empty state:** "No active sources. Browse below to add some."

Actions are inline — no page redirect needed.

### Browse Section (tabbed, below active sources)

Two tabs: **Scrolls** | **Books**

Within each tab, items grouped by `suggested_guild` as section headers with a horizontal rule divider. `nil` guild → "General" group, sorted last.

**Scrolls — click Add, done:**
- Pre-configured (URLs baked into `default_config`)
- "Add" immediately creates the source (paused), item moves to Active Sources
- No config step needed

**Books — click Add, expand inline config form:**
- Books need user-provided config (`repo_path`, `url`, `path`, etc.)
- Clicking "Add" expands the row in-place showing config fields derived from `default_config` keys
- "Save & Add" validates, creates the source (paused), row disappears from browse and appears in Active Sources
- "Cancel" collapses the row, nothing created

**Config fields per source_type:**
- `git` → repo path, branch, poll interval
- `directory` → path, file patterns, poll interval
- `feed` → URL, poll interval
- `webhook` → (no config needed — endpoint is auto-generated)
- `url` → URL, poll interval
- `websocket` → URL, message path, poll interval

**Shared behaviour:**
- Items already in stacks are hidden from browse list
- If all items in a category are added, category header hides too
- If all scrolls/books are added, tab shows "All added ✓"

### Active Sources — Editing Config

Each active source row is expandable. Expanded view shows:
- Editable config fields (same fields as the Add flow)
- Status, last run time
- Save, Pause/Resume, Delete actions

---

## Data Flow

```
mount/2
  sources = load all Source records
  stacked_book_ids = MapSet of book_ids from sources
  scroll_groups = Book.scrolls() |> reject already stacked |> group_by_guild
  book_groups = Book.books()   |> reject already stacked |> group_by_guild

handle_event("add_to_stacks", %{"book-id" => id})
  # Scrolls: create immediately
  insert Source (status: "paused", config: book.default_config)
  reload sources + rebuild groups

handle_event("expand_book", %{"book-id" => id})
  # Books: expand inline config form in browse row
  assign(expanding: id)

handle_event("save_book", %{"book-id" => id, "config" => params})
  # Books: validate + create
  merge params into book.default_config
  insert Source (status: "paused", config: merged_config)
  reload sources + rebuild groups
  # row disappears from browse, appears in active section

handle_event("save_source_config", %{"id" => id, "config" => params})
  # Edit existing source config
  update Source config
  reload sources

handle_event("resume", %{"id" => id})   → update status: "active", start worker
handle_event("pause",  %{"id" => id})   → update status: "paused", stop worker
handle_event("delete", %{"id" => id})   → delete record, stop worker

handle_event("resume", %{"id" => id})   → update status: "active", start worker
handle_event("pause",  %{"id" => id})   → update status: "paused", stop worker
handle_event("delete", %{"id" => id})   → delete record, stop worker
```

## Nav Changes

- Remove "Stacks" from nav
- "Library" nav item remains, path stays `/library`
- Router: `/stacks` can redirect to `/library` to avoid broken links

---

## What Goes Away

- `stacks_live.ex` — logic moves into `library_live.ex`
- "Stacks" nav entry in `root.html.heex`
- The `/stacks` route (replaced with redirect)
