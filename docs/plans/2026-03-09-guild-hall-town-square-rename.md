# Guild Hall / Town Square Rename Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename and restructure three pages: Members → Guild Hall (absorbing Town Square recruitment), Guild Hall → Town Square (pre-built charter browser), and remove Town Square as a standalone page.

**Architecture:** Three LiveView files are renamed/merged. `MembersLive` becomes `GuildHallLive` and gains the recruitment UI from `TownSquareLive`. The existing `GuildHallLive` (charter browser) becomes `TownSquareLive`. The old `TownSquareLive` is deleted. Routes, internal links, nav, and tests are all updated to match.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto, HEEx templates

---

## Task 1: Rename charter-browser LiveView — `GuildHallLive` → `TownSquareLive`

**Files:**
- Rename (copy+delete): `lib/ex_cortex_web/live/guild_hall_live.ex` → `lib/ex_cortex_web/live/town_square_live.ex`
- Replace: `lib/ex_cortex_web/live/town_square_live.ex` (old recruitment page — will be overwritten)

The old `TownSquareLive` (recruitment) will be completely replaced. The charter-browser content moves to `town_square_live.ex`.

**Step 1: Read the full current `guild_hall_live.ex`**

```bash
cat lib/ex_cortex_web/live/guild_hall_live.ex
```

**Step 2: Create new `town_square_live.ex` from `guild_hall_live.ex`**

Copy the entire file to `lib/ex_cortex_web/live/town_square_live.ex`, then make these changes:
- Module name: `ExCortexWeb.GuildHallLive` → `ExCortexWeb.TownSquareLive`
- `page_title: "Guild Hall"` → `page_title: "Town Square"`
- The heading in `render/1` (look for `"Guild Hall"` string): change to `"Town Square"`
- Internal link `/members` (in `push_navigate` after `build_own_guild`): change to `/guild-hall`
- `@post_install_redirect "/stacks"` stays as-is (stacks is still the redirect after install)

**Step 3: Delete the old `guild_hall_live.ex`**

```bash
rm lib/ex_cortex_web/live/guild_hall_live.ex
```

**Step 4: Verify compilation**

```bash
mix compile 2>&1 | grep -E "error|warning" | grep -v "^warning: redefining"
```

Expected: no errors (there will be a router warning since GuildHallLive is referenced there — that's fixed in Task 2).

---

## Task 2: Update router — swap routes and remove `/town-square` standalone route

**Files:**
- Modify: `lib/ex_cortex_web/router.ex`

**Step 1: Update the router**

Replace the three relevant live routes:

```elixir
# OLD:
live "/guild-hall", GuildHallLive, :index
live "/town-square", TownSquareLive, :index
live "/members", MembersLive, :index

# NEW:
live "/town-square", TownSquareLive, :index
live "/guild-hall", GuildHallLive, :index
```

- `/guild-hall` now maps to `GuildHallLive` (the new members+recruitment page — created in Task 3)
- `/town-square` now maps to `TownSquareLive` (the renamed charter browser — done in Task 1)
- `/members` is removed entirely

Full updated routes block:

```elixir
scope "/", ExCortexWeb do
  pipe_through :browser

  live_session :default, layout: {ExCortexWeb.Layouts, :app} do
    live "/", LodgeLive, :index
    live "/town-square", TownSquareLive, :index
    live "/guild-hall", GuildHallLive, :index
    live "/quests", QuestsLive, :index
    live "/quest-board", QuestBoardLive, :index
    live "/grimoire", GrimoireLive, :index
    live "/library", LibraryLive, :index
    live "/evaluate", EvaluateLive, :index
    live "/lodge", LodgeLive, :index
  end
end
```

**Step 2: Verify compilation**

```bash
mix compile 2>&1 | grep "error"
```

Expected: error about `GuildHallLive` not defined (the new one doesn't exist yet — fixed in Task 3). That's fine.

**Step 3: Commit tasks 1 and 2 together**

```bash
git add lib/ex_cortex_web/live/town_square_live.ex lib/ex_cortex_web/router.ex
git rm lib/ex_cortex_web/live/guild_hall_live.ex
git commit -m "feat: rename GuildHallLive→TownSquareLive (charter browser), update routes"
```

---

## Task 3: Create new `GuildHallLive` — Members + Recruitment merged

**Files:**
- Rename: `lib/ex_cortex_web/live/members_live.ex` → `lib/ex_cortex_web/live/guild_hall_live.ex`
- Delete: `lib/ex_cortex_web/live/members_live.ex` (after copy)

**Step 1: Copy `members_live.ex` to `guild_hall_live.ex`**

```bash
cp lib/ex_cortex_web/live/members_live.ex lib/ex_cortex_web/live/guild_hall_live.ex
```

**Step 2: Update module name and page title**

In `guild_hall_live.ex`:
- `defmodule ExCortexWeb.MembersLive` → `defmodule ExCortexWeb.GuildHallLive`
- `page_title: "Members"` → `page_title: "Guild Hall"`
- Any render heading `"Members"` → `"Guild Hall"`

**Step 3: Add recruitment imports and assigns to `guild_hall_live.ex`**

At the top of the module, add the imports that TownSquareLive used:

```elixir
import SaladUI.Badge

alias ExCortex.Members.BuiltinMember
```

(Check if `SaladUI.Badge` is already imported — `members_live.ex` likely imports it for rank badges. Add only what's missing.)

In `mount/3`, add to the assigns:

```elixir
editors: BuiltinMember.editors(),
analysts: BuiltinMember.analysts(),
specialists: BuiltinMember.specialists(),
advisors: BuiltinMember.advisors(),
```

**Step 4: Add `handle_event("recruit", ...)` to `guild_hall_live.ex`**

Add this event handler (copy from old `town_square_live.ex`, updating the redirect):

```elixir
@impl true
def handle_event("recruit", %{"member-id" => member_id, "rank" => rank}, socket) do
  member = BuiltinMember.get(member_id)
  rank_atom = String.to_existing_atom(rank)
  rank_config = member.ranks[rank_atom]

  attrs = %{
    type: "role",
    name: member.name,
    status: "active",
    source: "db",
    team: member.category,
    config: %{
      "member_id" => member_id,
      "system_prompt" => member.system_prompt,
      "rank" => rank,
      "model" => rank_config.model,
      "strategy" => rank_config.strategy
    }
  }

  %Excellence.Schemas.Member{}
  |> Excellence.Schemas.Member.changeset(attrs)
  |> ExCortex.Repo.insert(on_conflict: :nothing)

  {:noreply,
   socket
   |> put_flash(:info, "#{member.name} (#{rank}) recruited!")
   |> push_navigate(to: "/guild-hall")}
end
```

**Step 5: Add recruitment section to the render/template in `guild_hall_live.ex`**

At the bottom of the render (after the existing members list), add a "Recruit a Member" section. Copy the `member_section/1` and `member_row/1` private component functions from old `town_square_live.ex` into `guild_hall_live.ex`, then add this to the render body:

```heex
<div>
  <h2 class="text-lg font-semibold mb-1">Recruit a Member</h2>
  <p class="text-sm text-muted-foreground mb-5">
    Add a pre-configured member role to your guild.
  </p>
  <div class="space-y-10">
    <.member_section title="Editors" description="Text quality and writing review" members={@editors} />
    <.member_section title="Analysts" description="Data interpretation and pattern recognition" members={@analysts} />
    <.member_section title="Specialists" description="Domain-specific technical expertise" members={@specialists} />
    <.member_section title="Advisors" description="Perspective, judgment, and risk assessment" members={@advisors} />
  </div>
</div>
```

Note: Remove the `has_guild` prop from `member_section` and `member_row` — in the new Guild Hall page, recruitment is always available (the user is already on their own members page).

Updated `member_section/1`:

```elixir
defp member_section(assigns) do
  ~H"""
  <div>
    <h3 class="text-base font-semibold mb-1">{@title}</h3>
    <p class="text-muted-foreground text-sm mb-4">{@description}</p>
    <div class="space-y-3">
      <%= for member <- @members do %>
        <.member_row member={member} />
      <% end %>
    </div>
  </div>
  """
end
```

Updated `member_row/1`:

```elixir
defp member_row(assigns) do
  ~H"""
  <div class="flex flex-col gap-4 rounded-lg border p-5 sm:flex-row sm:items-center sm:justify-between">
    <div class="space-y-1">
      <div class="flex items-center gap-2">
        <span class="font-medium">{@member.name}</span>
        <.badge variant="secondary">{@member.category}</.badge>
      </div>
      <p class="text-sm text-muted-foreground">{@member.description}</p>
    </div>
    <div class="shrink-0 flex gap-2 self-start sm:self-auto">
      <.button size="sm" variant="outline" phx-click="recruit" phx-value-member-id={@member.id} phx-value-rank="apprentice">
        Apprentice
      </.button>
      <.button size="sm" variant="outline" phx-click="recruit" phx-value-member-id={@member.id} phx-value-rank="journeyman">
        Journeyman
      </.button>
      <.button size="sm" phx-click="recruit" phx-value-member-id={@member.id} phx-value-rank="master">
        Master
      </.button>
    </div>
  </div>
  """
end
```

**Step 6: Delete `members_live.ex`**

```bash
rm lib/ex_cortex_web/live/members_live.ex
```

**Step 7: Verify compilation**

```bash
mix compile 2>&1 | grep -E "^error"
```

Expected: no errors.

**Step 8: Commit**

```bash
git add lib/ex_cortex_web/live/guild_hall_live.ex
git rm lib/ex_cortex_web/live/members_live.ex
git commit -m "feat: create GuildHallLive — members roster + recruitment merged from TownSquare"
```

---

## Task 4: Fix all internal links

**Files:**
- Modify: `lib/ex_cortex_web/live/lodge_live.ex`
- Modify: `lib/ex_cortex_web/live/town_square_live.ex` (the new one — charter browser)
- Check: any remaining `/members` or `/guild-hall` (old meaning) references

**Step 1: Update `lodge_live.ex`**

Find line:
```elixir
{:ok, push_navigate(socket, to: "/guild-hall")}
```

The lodge redirects here when no guild is installed. The charter browser (install guilds) is now at `/town-square`:

```elixir
{:ok, push_navigate(socket, to: "/town-square")}
```

**Step 2: Check `town_square_live.ex` (new — charter browser) for any `/members` links**

The old `guild_hall_live.ex` had:
- `push_navigate(to: "/members")` in `build_own_guild` event → change to `/guild-hall`

Verify and fix:

```bash
grep -n "/members\|/guild-hall\|/town-square" lib/ex_cortex_web/live/town_square_live.ex
```

Update any `/members` reference to `/guild-hall`.

**Step 3: Scan all remaining files for stale paths**

```bash
grep -rn '"/members"\|"/guild-hall"\|"/town-square"' lib/ --include="*.ex" --include="*.heex"
```

Fix any remaining references:
- `/members` → `/guild-hall`
- `/guild-hall` (old charter browser context) → `/town-square`
- `/town-square` (old recruitment context) → `/guild-hall`

**Step 4: Verify compilation**

```bash
mix compile 2>&1 | grep "error"
```

**Step 5: Commit**

```bash
git add -u
git commit -m "fix: update all internal links after Guild Hall / Town Square rename"
```

---

## Task 5: Update navigation

**Files:**
- Modify: `lib/ex_cortex_web/components/layouts/root.html.heex`

**Step 1: Update the nav links list**

Current nav:
```elixir
{"Lodge", "/lodge"},
{"Members", "/members"},
{"Quests", "/quests"},
{"Library", "/library"},
{"Quest Board", "/quest-board"},
{"Town Square", "/town-square"},
{"Guild Hall", "/guild-hall"}
```

New nav (Members removed, Guild Hall and Town Square swapped in meaning):
```elixir
{"Lodge", "/lodge"},
{"Guild Hall", "/guild-hall"},
{"Quests", "/quests"},
{"Library", "/library"},
{"Quest Board", "/quest-board"},
{"Town Square", "/town-square"}
```

**Step 2: Verify compilation**

```bash
mix compile 2>&1 | grep "error"
```

**Step 3: Commit**

```bash
git add lib/ex_cortex_web/components/layouts/root.html.heex
git commit -m "feat: update nav — Guild Hall replaces Members, Town Square is charter browser"
```

---

## Task 6: Update and rename test files

**Files:**
- Rename: `test/ex_cortex_web/live/members_live_test.exs` → `test/ex_cortex_web/live/guild_hall_live_test.exs`
- Rename: `test/ex_cortex_web/live/guild_hall_live_test.exs` → `test/ex_cortex_web/live/town_square_live_test.exs`
- Delete: `test/ex_cortex_web/live/town_square_live_test.exs` (after merging key tests into guild_hall_live_test.exs)

**Step 1: Rename and update `members_live_test.exs` → `guild_hall_live_test.exs`**

```bash
cp test/ex_cortex_web/live/members_live_test.exs test/ex_cortex_web/live/guild_hall_live_test.exs
rm test/ex_cortex_web/live/members_live_test.exs
```

In `guild_hall_live_test.exs`:
- `defmodule ExCortexWeb.MembersLiveTest` → `defmodule ExCortexWeb.GuildHallLiveTest`
- All `live(conn, "/members")` → `live(conn, "/guild-hall")`
- `assert html =~ "Members"` → `assert html =~ "Guild Hall"`

Add a recruitment test at the bottom (new `describe "recruitment"` block):

```elixir
describe "recruitment" do
  test "shows recruit sections", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/guild-hall")
    assert html =~ "Recruit a Member"
    assert html =~ "Editors"
    assert html =~ "Analysts"
  end

  test "recruit button creates a member and stays on guild hall", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/guild-hall")
    # Click recruit for the first builtin member at apprentice rank
    first = hd(ExCortex.Members.BuiltinMember.editors())
    html = render_click(view, "recruit", %{"member-id" => first.id, "rank" => "apprentice"})
    # Flash appears and member is in DB
    assert ExCortex.Repo.get_by(Excellence.Schemas.Member, name: first.name)
  end
end
```

**Step 2: Rename and update `guild_hall_live_test.exs` → `town_square_live_test.exs`**

```bash
cp test/ex_cortex_web/live/guild_hall_live_test.exs test/ex_cortex_web/live/town_square_live_test.exs
```

In `town_square_live_test.exs`:
- `defmodule ExCortexWeb.GuildHallLiveTest` → `defmodule ExCortexWeb.TownSquareLiveTest`
- `live(conn, "/guild-hall")` → `live(conn, "/town-square")`
- `assert html =~ "Guild Hall"` → `assert html =~ "Town Square"`

**Step 3: Delete the old `guild_hall_live_test.exs` and old `town_square_live_test.exs`**

```bash
rm test/ex_cortex_web/live/guild_hall_live_test.exs
rm test/ex_cortex_web/live/town_square_live_test.exs
```

Wait — step 2 already created the new `town_square_live_test.exs`. The file to delete here is only the OLD one (from before step 2). Since step 2 overwrites it, just delete `guild_hall_live_test.exs`:

```bash
rm test/ex_cortex_web/live/guild_hall_live_test.exs
```

**Step 4: Run the full test suite**

```bash
mix test --seed 0 2>&1 | tail -10
```

Expected: all tests pass (or only the 3 pre-existing lore/grimoire failures which are unrelated).

**Step 5: Commit**

```bash
git add test/ex_cortex_web/live/guild_hall_live_test.exs test/ex_cortex_web/live/town_square_live_test.exs
git rm test/ex_cortex_web/live/members_live_test.exs
git commit -m "test: rename and update tests for Guild Hall / Town Square rename"
```

---

## Summary

| Before | After | Route |
|--------|-------|-------|
| `MembersLive` — member roster | `GuildHallLive` — member roster + recruitment | `/guild-hall` |
| `GuildHallLive` — charter browser | `TownSquareLive` — charter browser | `/town-square` |
| `TownSquareLive` — recruitment | *(merged into GuildHallLive)* | *(removed)* |

Nav: Lodge · Guild Hall · Quests · Library · Quest Board · Town Square
