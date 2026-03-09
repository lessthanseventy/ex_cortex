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

**Key behaviour:**
- Items already in the user's stacks are **hidden** from the browse list
- Clicking "Add" immediately creates the source (paused), moves it from browse into the Active Sources section — no redirect
- If all items in a category are added, the category header hides too
- If all scrolls/books are added, the tab shows "All added ✓"

---

## Data Flow

```
mount/2
  sources = load all Source records
  stacked_book_ids = MapSet of book_ids from sources
  scroll_groups = Book.scrolls() |> reject already stacked |> group_by_guild
  book_groups = Book.books()   |> reject already stacked |> group_by_guild

handle_event("add_to_stacks", %{"book-id" => id})
  insert Source (status: "paused")
  reload sources + rebuild groups
  # item disappears from browse, appears in active section

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
