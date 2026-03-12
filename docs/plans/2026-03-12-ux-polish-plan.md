# UX Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Make ExCalibur's UI more connected and discoverable: reorder nav, add tooltips, standardize headers, improve empty states, add cross-page links, and add context summaries.

**Architecture:** All changes are in LiveView render functions and the root layout template. No schema changes, no new routes. Cross-links use existing query functions. Context summaries are computed from data already loaded in mount.

**Tech Stack:** Elixir, Phoenix LiveView, HEEx templates, SaladUI components

**Design Doc:** docs/plans/2026-03-12-ux-polish-design.md

---

## Dependency Graph

```
Task 0: Nav reorder + tooltips ──────────────────┐
Task 1: Settings header ─────────────────────────┤
Task 2: Empty states (Grimoire, Quests) ─────────┤ (all independent)
Task 3: Context summaries ◄── Task 0             │
Task 4: Cross-links (Guild Hall) ────────────────┤
Task 5: Cross-links (Quests) ────────────────────┤
Task 6: Cross-links (Library) ───────────────────┤
Task 7: Lodge empty state + context ─────────────┤
Task 8: Full test pass ◄── Tasks 0-7 ────────────┘
```

Tasks 0-2, 4-7 can all run in parallel. Task 3 depends on Task 0 (nav order). Task 8 is final.

---

### Task 0: Nav reorder + tooltips (depends: none)

**Files:**
- Modify: `lib/ex_calibur_web/components/layouts/root.html.heex`

**Step 1: No test needed — template-only change**

**Step 2: Update the nav link list and add title attributes**

In `lib/ex_calibur_web/components/layouts/root.html.heex`, replace lines 31-53:

```heex
        <div class="flex overflow-x-auto">
          <%= for {label, path, tooltip} <- [
            {"Town Square", ~p"/town-square", "Choose your guild and banner"},
            {"Guild Hall", ~p"/guild-hall", "Manage members, roles, and charters"},
            {"Quests", ~p"/quests", "Build workflows and set triggers"},
            {"Library", ~p"/library", "Sources, scrolls, books, and dictionaries"},
            {"Lodge", ~p"/lodge", "Bulletin board — notes, alerts, quest output"},
            {"Grimoire", ~p"/grimoire", "Quest history and accumulated lore"},
            {"Settings", ~p"/settings", "Tool and integration configuration"}
          ] do %>
            <a
              href={path}
              title={tooltip}
              class={[
                "px-4 py-4 text-sm whitespace-nowrap transition-colors border-b-2",
                if(String.starts_with?(@conn.request_path, path),
                  do: "border-foreground text-foreground font-medium",
                  else:
                    "border-transparent text-muted-foreground hover:text-foreground hover:border-muted-foreground"
                )
              ]}
            >
              {label}
            </a>
          <% end %>
        </div>
```

**Step 3: Verify in browser**

Start server and check nav order is Town Square → Guild Hall → Quests → Library → Lodge → Grimoire → Settings, and hovering shows tooltips.

**Step 4: Commit**

```bash
git add lib/ex_calibur_web/components/layouts/root.html.heex
git commit -m "feat: reorder nav to match workflow and add tooltips"
```

---

### Task 1: Settings header standardization (depends: none)

**Files:**
- Modify: `lib/ex_calibur_web/live/settings_live.ex`

**Step 1: No test needed — template-only change**

**Step 2: Update the header in the render function**

In `lib/ex_calibur_web/live/settings_live.ex`, replace lines 81-82:

```elixir
    <div class="max-w-2xl mx-auto p-6 space-y-8">
      <h1 class="text-2xl font-bold">Settings</h1>
```

With:

```elixir
    <div class="max-w-2xl mx-auto p-6 space-y-8">
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Settings</h1>
        <p class="text-muted-foreground mt-1.5">
          Configure tool integrations and external service connections.
        </p>
      </div>
```

**Step 3: Commit**

```bash
git add lib/ex_calibur_web/live/settings_live.ex
git commit -m "feat: standardize Settings header to match other pages"
```

---

### Task 2: Improved empty states (Grimoire + Quests) (depends: none)

**Files:**
- Modify: `lib/ex_calibur_web/live/grimoire_live.ex`
- Modify: `lib/ex_calibur_web/live/quests_live.ex`

**Step 1: No tests needed — text-only template changes**

**Step 2: Update Grimoire empty states**

In `lib/ex_calibur_web/live/grimoire_live.ex`:

Replace line 160-164 ("No quests yet" block):

```heex
                  <p class="text-muted-foreground text-sm">
                    No quests yet. Create one from the
                    <a href="/quests" class="underline text-primary">Quests</a>
                    page.
                  </p>
```

With:

```heex
                  <p class="text-muted-foreground text-sm">
                    No quests yet. Create one from the
                    <a href="/quests" class="underline text-primary">Quests</a>
                    page. Once quests run, their history and lore entries show up here.
                  </p>
```

Replace line 301 ("No runs yet."):

```heex
            <p class="text-sm text-muted-foreground">No runs yet.</p>
```

With:

```heex
            <p class="text-sm text-muted-foreground">
              No runs yet. Run this quest from the
              <a href="/quests" class="underline text-primary">Quests</a>
              page, or set a trigger to run it automatically.
            </p>
```

Replace line 338 ("No lore entries yet."):

```heex
            <p class="text-sm text-muted-foreground">No lore entries yet.</p>
```

With:

```heex
            <p class="text-sm text-muted-foreground">
              No lore entries yet. Lore is written by quest steps as they process input.
            </p>
```

**Step 3: Update Quests empty state**

In `lib/ex_calibur_web/live/quests_live.ex`, replace lines 524-528:

```heex
            <div class="text-center py-12 text-muted-foreground">
              <p class="text-sm">
                No quests yet. Create one in Quest Templates → Custom below.
              </p>
            </div>
```

With:

```heex
            <div class="text-center py-12 text-muted-foreground">
              <p class="text-sm">
                No quests yet. Install one from the Quest Board above, or create your own.
              </p>
            </div>
```

**Step 4: Commit**

```bash
git add lib/ex_calibur_web/live/grimoire_live.ex lib/ex_calibur_web/live/quests_live.ex
git commit -m "feat: improve empty states with contextual guidance and links"
```

---

### Task 3: Context summaries on page headers (depends: Task 0)

**Files:**
- Modify: `lib/ex_calibur_web/live/guild_hall_live.ex`
- Modify: `lib/ex_calibur_web/live/quests_live.ex`
- Modify: `lib/ex_calibur_web/live/grimoire_live.ex`
- Modify: `lib/ex_calibur_web/live/library_live.ex`
- Modify: `lib/ex_calibur_web/live/town_square_live.ex`

**Step 1: Guild Hall context line**

In `lib/ex_calibur_web/live/guild_hall_live.ex`, the header is inside the render function. Find the tagline paragraph:

```heex
      <p class="text-muted-foreground mt-1.5">
        Guild roles — each member runs evaluations with their own model and strategy.
      </p>
```

Add after it:

```heex
      <p class="text-sm text-muted-foreground">
        {length(@members)} members · {Enum.count(@members, & &1.active)} active
      </p>
```

**Step 2: Quests context line**

In `lib/ex_calibur_web/live/quests_live.ex`, find the tagline:

```heex
      <p class="text-muted-foreground mt-1.5">
        Structured workflows — build steps, set a trigger, run on demand or on schedule.
      </p>
```

Add after it:

```heex
      <p class="text-sm text-muted-foreground">
        {length(@quests)} quests · {Enum.count(@quests, &(&1.trigger == "scheduled"))} scheduled · {Enum.count(@quests, &(&1.trigger == "source"))} source-triggered
      </p>
```

**Step 3: Grimoire context line**

In `lib/ex_calibur_web/live/grimoire_live.ex`, this only shows when no quest is selected (line 143-148). Find:

```heex
        <div>
          <h1 class="text-3xl font-bold tracking-tight">Grimoire</h1>
          <p class="text-muted-foreground mt-1.5">
            Quest log and telemetry for your guild's missions.
          </p>
        </div>
```

Replace with (adding lore count to mount and context line):

```heex
        <div>
          <h1 class="text-3xl font-bold tracking-tight">Grimoire</h1>
          <p class="text-muted-foreground mt-1.5">
            Quest log and telemetry for your guild's missions.
          </p>
          <p class="text-sm text-muted-foreground">
            {length(@quests)} quests tracked · {Enum.sum(Enum.map(@run_stats, fn {_id, s} -> s.total end))} runs total
          </p>
        </div>
```

**Step 4: Library context line**

In `lib/ex_calibur_web/live/library_live.ex`, find:

```heex
      <p class="text-muted-foreground mt-1.5">
        Manage active sources and browse scrolls and books to add more.
      </p>
```

Add after it (the assigns `@sources`, `@dictionaries` are already loaded in mount):

```heex
      <p class="text-sm text-muted-foreground">
        {length(@sources)} sources active · {length(@dictionaries)} dictionaries
      </p>
```

Note: check that `@dictionaries` is assigned in mount. If not, add it. The Library mount already loads dictionaries for the dictionaries tab.

**Step 5: Town Square context line**

In `lib/ex_calibur_web/live/town_square_live.ex`, the banner-set view (line 257-262) shows "Town Square" with tagline. Find:

```heex
          <p class="text-muted-foreground mt-1.5">
            Choose your guild. Installing a new guild replaces the current one.
          </p>
```

Add after it:

```heex
          <%= if @current_guild do %>
            <p class="text-sm text-muted-foreground">
              Current guild: {@current_guild}
            </p>
          <% end %>
```

The `@current_guild` assign is already set in the TownSquareLive mount.

**Step 6: Commit**

```bash
git add lib/ex_calibur_web/live/guild_hall_live.ex lib/ex_calibur_web/live/quests_live.ex lib/ex_calibur_web/live/grimoire_live.ex lib/ex_calibur_web/live/library_live.ex lib/ex_calibur_web/live/town_square_live.ex
git commit -m "feat: add context summary lines to page headers"
```

---

### Task 4: Cross-links — Guild Hall members → Quests (depends: none)

**Files:**
- Modify: `lib/ex_calibur_web/live/guild_hall_live.ex`

**Step 1: Add quest lookup to mount**

In `mount_guild_hall/1`, after loading members, add a lookup map of member name → quest names:

```elixir
    quests = ExCalibur.Quests.list_quests()

    member_quests =
      Map.new(members, fn m ->
        matching =
          Enum.filter(quests, fn q ->
            Enum.any?(q.steps || [], fn step ->
              Enum.any?(step["roster"] || [], fn r -> r["who"] == m.name end)
            end)
          end)

        {m.name, Enum.map(matching, & &1.name)}
      end)
```

Add `member_quests: member_quests` to the assigns.

**Step 2: Show quest links on member card**

In the `member_card` component, after the name/team/rank row (around line 298), add:

```heex
          <%= if @member_quests != [] do %>
            <p class="text-xs text-muted-foreground mt-0.5">
              Used in: {Enum.join(@member_quests, ", ")}
            </p>
          <% end %>
```

Add the attr to the component:

```elixir
attr :member_quests, :list, default: []
```

Update the call site to pass the quests:

```heex
<.member_card
  ...
  member_quests={Map.get(@member_quests, member.name, [])}
/>
```

**Step 3: Commit**

```bash
git add lib/ex_calibur_web/live/guild_hall_live.ex
git commit -m "feat: show quest usage on Guild Hall member cards"
```

---

### Task 5: Cross-links — Quests → Sources and Members (depends: none)

**Files:**
- Modify: `lib/ex_calibur_web/live/quests_live.ex`

**Step 1: Add source name lookup**

The quests mount already loads `@sources`. Source-triggered quests have `source_ids` field. In the quest card component or quest detail area, when a quest has `trigger == "source"` and `source_ids`, show the source names.

Find where trigger info is displayed in the quest card. Add after the trigger display:

```heex
<%= if quest.trigger == "source" and quest.source_ids != [] do %>
  <p class="text-xs text-muted-foreground">
    Triggered by: {Enum.map_join(quest.source_ids, ", ", fn sid ->
      case Enum.find(@sources, &(to_string(&1.id) == sid)) do
        nil -> sid
        s -> source_name(s)
      end
    end)}
  </p>
<% end %>
```

Read the quest card component in quests_live.ex to find the exact insertion point. The source name helper likely already exists (used in Library).

**Step 2: Add member references in step detail**

In the quest detail expansion, steps show their roster. If roster entries reference member names, those are already visible. Add a subtle link:

```heex
<a href="/guild-hall" class="text-xs text-muted-foreground hover:text-primary underline">
  view in Guild Hall
</a>
```

This goes near where roster is displayed in the expanded quest step section.

**Step 3: Commit**

```bash
git add lib/ex_calibur_web/live/quests_live.ex
git commit -m "feat: show source names on source-triggered quests"
```

---

### Task 6: Cross-links — Library sources → Quests (depends: none)

**Files:**
- Modify: `lib/ex_calibur_web/live/library_live.ex`

**Step 1: Add quest lookup to mount**

In the Library mount, after loading sources, build a source_id → quest_names map:

```elixir
    quests = ExCalibur.Quests.list_quests()

    source_quests =
      Map.new(sources, fn s ->
        matching =
          Enum.filter(quests, fn q ->
            q.trigger == "source" and to_string(s.id) in (q.source_ids || [])
          end)

        {s.id, Enum.map(matching, & &1.name)}
      end)
```

Add `source_quests: source_quests` to assigns.

**Step 2: Show quest links on source row**

In the `source_row` component (around line 1191, after the "Last run" line), add:

```heex
            <%= if @quest_names != [] do %>
              <p class="text-xs text-muted-foreground mt-0.5">
                Triggers: {Enum.join(@quest_names, ", ")}
              </p>
            <% end %>
```

Add `attr :quest_names, :list, default: []` to the component attrs.

Update the call site to pass `quest_names={Map.get(@source_quests, source.id, [])}`.

**Step 3: Commit**

```bash
git add lib/ex_calibur_web/live/library_live.ex
git commit -m "feat: show triggered quests on Library source rows"
```

---

### Task 7: Lodge empty state + context summary (depends: none)

**Files:**
- Modify: `lib/ex_calibur_web/live/lodge_live.ex`

**Step 1: Update the empty state message**

In `lib/ex_calibur_web/live/lodge_live.ex`, replace lines 325-329:

```heex
          <div class="rounded-lg border p-8 text-center">
            <p class="text-muted-foreground text-sm">
              No cards yet. Add one above or run a quest that posts to the Lodge.
            </p>
          </div>
```

With:

```heex
          <div class="rounded-lg border p-8 text-center">
            <p class="text-muted-foreground text-sm">
              No cards yet. Cards appear here when quests run, or you can create one above.
            </p>
            <p class="text-xs text-muted-foreground mt-2">
              Set up quests from the <a href="/quests" class="underline text-primary">Quests</a> page.
            </p>
          </div>
```

**Step 2: Add context summary to Lodge header**

Find the header (lines 218-223):

```heex
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Lodge</h1>
        <p class="text-muted-foreground mt-1.5">
          Your guild's dashboard — pinned cards, quest output, and notes.
        </p>
      </div>
```

Replace with:

```heex
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Lodge</h1>
        <p class="text-muted-foreground mt-1.5">
          Your guild's dashboard — pinned cards, quest output, and notes.
        </p>
        <p class="text-sm text-muted-foreground">
          {length(@cards)} cards · {length(@pinned_cards)} pinned
        </p>
      </div>
```

**Step 3: Commit**

```bash
git add lib/ex_calibur_web/live/lodge_live.ex
git commit -m "feat: improve Lodge empty state and add context summary"
```

---

### Task 8: Full test pass (depends: Tasks 0-7)

**Step 1: Format**

```bash
mix format
```

**Step 2: Run all tests**

```bash
mix test
```

**Step 3: Fix any failures**

If any tests reference nav order or specific empty state text, update them.

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "style: format and fix tests after UX polish"
```
