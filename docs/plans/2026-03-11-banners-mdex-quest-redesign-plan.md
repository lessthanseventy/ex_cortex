# Banners, MDEx & Quest Board Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Introduce app-wide banner scoping (Tech/Lifestyle/Business), MDEx-powered Markdown rendering for all content, and a redesigned quest board with nested collapsible steps and three install paths.

**Architecture:** Settings table stores the single-tenant banner choice. Banner tags are compile-time attributes on charter/template/member/book structs, filtered in LiveView mounts. MDEx renders all authored text via `~MD` sigil with HEEX modifier. Quest board cards nest step cards with expand/collapse, and expose "Recruit & Go" (turnkey), "Customize" (edit-then-install), and "Custom" (build from scratch) paths.

**Tech Stack:** Phoenix LiveView, Ecto, MDEx (`~> 0.11`), mdex_mermaid plugin, SaladUI components, TailwindCSS.

---

## Task 1: Add MDEx Dependency

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/mix.exs`

**Step 1: Add mdex to deps**

In `/home/andrew/projects/ex_cortex/mix.exs`, add to the `deps` function:

```elixir
{:mdex, "~> 0.11"},
```

Add it after the `{:salad_ui, ...}` line.

**Step 2: Fetch deps**

Run: `mix deps.get`
Expected: mdex and its Rust NIF compile successfully.

**Step 3: Verify it works**

Run: `iex -S mix` then `MDEx.to_html!("# Hello")`
Expected: `"<h1>Hello</h1>"`

**Step 4: Commit**

```bash
git add mix.exs mix.lock
git commit -m "deps: add mdex for Markdown rendering"
```

---

## Task 2: Settings Schema, Migration & Context

**Files:**
- Create: `/home/andrew/projects/ex_cortex/lib/ex_cortex/settings.ex`
- Create: `priv/repo/migrations/TIMESTAMP_create_settings.exs`
- Create: `/home/andrew/projects/ex_cortex/test/ex_cortex/settings_test.exs`

**Step 1: Write the failing test**

Create `/home/andrew/projects/ex_cortex/test/ex_cortex/settings_test.exs`:

```elixir
defmodule ExCortex.SettingsTest do
  use ExCortex.DataCase

  alias ExCortex.Settings

  describe "banner" do
    test "get_banner/0 returns nil when no settings exist" do
      assert Settings.get_banner() == nil
    end

    test "set_banner/1 stores and returns the banner" do
      assert {:ok, _} = Settings.set_banner("tech")
      assert Settings.get_banner() == "tech"
    end

    test "set_banner/1 updates existing banner" do
      {:ok, _} = Settings.set_banner("tech")
      {:ok, _} = Settings.set_banner("lifestyle")
      assert Settings.get_banner() == "lifestyle"
    end

    test "set_banner/1 validates banner value" do
      assert {:error, changeset} = Settings.set_banner("invalid")
      assert %{banner: ["is invalid"]} = errors_on(changeset)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex/settings_test.exs`
Expected: Compilation error — `Settings` module doesn't exist.

**Step 3: Create the migration**

Run: `mix ecto.gen.migration create_settings`

Then edit the generated migration file:

```elixir
defmodule ExCortex.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings) do
      add :banner, :string

      timestamps()
    end
  end
end
```

**Step 4: Create the Settings context**

Create `/home/andrew/projects/ex_cortex/lib/ex_cortex/settings.ex`:

```elixir
defmodule ExCortex.Settings do
  @moduledoc "App-wide settings (single-row table)."

  use Ecto.Schema
  import Ecto.Changeset

  @valid_banners ~w(tech lifestyle business)

  schema "settings" do
    field :banner, :string

    timestamps()
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:banner])
    |> validate_inclusion(:banner, @valid_banners)
  end

  def get_banner do
    case ExCortex.Repo.one(__MODULE__) do
      nil -> nil
      settings -> settings.banner
    end
  end

  def set_banner(banner) do
    case ExCortex.Repo.one(__MODULE__) do
      nil -> %__MODULE__{}
      existing -> existing
    end
    |> changeset(%{banner: banner})
    |> ExCortex.Repo.insert_or_update()
  end
end
```

**Step 5: Run migration and tests**

Run: `mix ecto.migrate && mix test test/ex_cortex/settings_test.exs`
Expected: All 4 tests pass.

**Step 6: Commit**

```bash
git add lib/ex_cortex/settings.ex test/ex_cortex/settings_test.exs priv/repo/migrations/*_create_settings.exs
git commit -m "feat: add Settings schema with banner persistence"
```

---

## Task 3: Banner Tags on Charters

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/town_square_live.ex`

**Step 1: Write the failing test**

Create `/home/andrew/projects/ex_cortex/test/ex_cortex/banner_tags_test.exs`:

```elixir
defmodule ExCortex.BannerTagsTest do
  use ExUnit.Case, async: true

  describe "charter banners" do
    test "all charters have a banner tag" do
      for {_name, mod} <- ExCortexWeb.TownSquareLive.charters() do
        meta = mod.metadata()
        assert meta[:banner] in [:tech, :lifestyle, :business],
               "#{meta.name} missing banner tag"
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex/banner_tags_test.exs`
Expected: Fails — `charters/0` not exported or `banner` key missing from metadata.

**Step 3: Expose charters and add banner to each charter's metadata**

First, expose the `@charters` map via a public function in `town_square_live.ex`. Add near the top of the module:

```elixir
def charters, do: @charters
```

Then add a `:banner` key to each charter module's `metadata/0` return map. The mapping:

**Tech banner:**
- `CodeReview`, `AccessibilityReview`, `DependencyAudit`, `IncidentTriage`, `PerformanceAudit`, `QualityCollective`, `PlatformGuild`, `TheSkeptics`, `TechDispatch`

**Lifestyle banner:**
- `ContentModeration`, `CreativeStudio`, `EverydayCouncil`, `SportsCorner`, `CultureDesk`, `ScienceWatch`

**Business banner:**
- `ContractReview`, `RiskAssessment`, `ProductIntelligence`, `MarketSignals`

For each charter module (e.g. `/home/andrew/projects/ex_cortex/lib/ex_cortex/charters/code_review.ex`), add `banner: :tech` to the map returned by `metadata/0`.

Example for CodeReview:
```elixir
def metadata do
  %{
    banner: :tech,
    name: "Code Review",
    # ... rest unchanged
  }
end
```

Repeat for all 19 charters with the appropriate banner atom.

**Step 4: Run tests**

Run: `mix test test/ex_cortex/banner_tags_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex/charters/*.ex lib/ex_cortex_web/live/town_square_live.ex test/ex_cortex/banner_tags_test.exs
git commit -m "feat: add banner tags to all 19 guild charters"
```

---

## Task 4: Banner Tags on Board Templates

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex/board.ex` (struct)
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex/board/triage.ex`
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex/board/reporting.ex`
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex/board/generation.ex`
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex/board/review.ex`
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex/board/onboarding.ex`
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex/board/lifestyle.ex`

**Step 1: Write the failing test**

Create `/home/andrew/projects/ex_cortex/test/ex_cortex/board_banners_test.exs`:

```elixir
defmodule ExCortex.BoardBannersTest do
  use ExUnit.Case, async: true

  alias ExCortex.Board

  describe "board template banners" do
    test "all templates have a banner tag" do
      for template <- Board.all() do
        assert template.banner in [:tech, :lifestyle, :business],
               "Template #{template.id} missing banner tag"
      end
    end

    test "filter_by_banner/1 returns only matching templates" do
      tech = Board.filter_by_banner(:tech)
      assert length(tech) > 0
      assert Enum.all?(tech, &(&1.banner == :tech))
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex/board_banners_test.exs`
Expected: Fails — `:banner` not in struct / `filter_by_banner` undefined.

**Step 3: Add `:banner` to Board struct**

In `/home/andrew/projects/ex_cortex/lib/ex_cortex/board.ex`, add `:banner` to the defstruct:

```elixir
defstruct [
  :id,
  :name,
  :category,
  :banner,
  :description,
  :suggested_team,
  :requires,
  :step_definitions,
  :quest_definition,
  source_definitions: []
]
```

Add filter function:

```elixir
def filter_by_banner(banner) do
  Enum.filter(all(), &(&1.banner == banner))
end
```

**Step 4: Add banner to each template definition**

Mapping by category:
- **Triage** (5 templates): all `:tech`
- **Reporting** (4 templates): all `:tech` (except any lifestyle-oriented ones — check descriptions)
- **Generation** (6 templates): all `:tech`
- **Review** (6 templates): all `:tech`
- **Onboarding** (4 templates): split by description — tech-focused get `:tech`, general get `:business`
- **Lifestyle** (6 templates): all `:lifestyle`

In each template struct in the category modules, add `banner: :tech` (or `:lifestyle` / `:business` as appropriate). Example in `board/triage.ex`:

```elixir
%Board{
  id: "jira_ticket_triage",
  banner: :tech,
  name: "Jira Ticket Triage",
  # ... rest unchanged
}
```

**Step 5: Run tests**

Run: `mix test test/ex_cortex/board_banners_test.exs`
Expected: Pass.

**Step 6: Commit**

```bash
git add lib/ex_cortex/board.ex lib/ex_cortex/board/*.ex test/ex_cortex/board_banners_test.exs
git commit -m "feat: add banner tags to all board templates"
```

---

## Task 5: Banner Tags on Builtin Members

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex/members/member.ex`

**Step 1: Write the failing test**

Create `/home/andrew/projects/ex_cortex/test/ex_cortex/member_banners_test.exs`:

```elixir
defmodule ExCortex.MemberBannersTest do
  use ExUnit.Case, async: true

  alias ExCortex.Members.BuiltinMember

  describe "builtin member banners" do
    test "all members have a banner tag" do
      for member <- BuiltinMember.all() do
        assert member.banner in [:tech, :lifestyle, :business],
               "Member #{member.id} missing banner tag"
      end
    end

    test "filter_by_banner/1 returns matching members" do
      tech = BuiltinMember.filter_by_banner(:tech)
      assert length(tech) > 0
      assert Enum.all?(tech, &(&1.banner == :tech))
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex/member_banners_test.exs`
Expected: Fails — `:banner` not in BuiltinMember struct.

**Step 3: Add `:banner` to BuiltinMember struct and tag all members**

In `/home/andrew/projects/ex_cortex/lib/ex_cortex/members/member.ex`:

Add `:banner` to defstruct:

```elixir
defstruct [:id, :name, :description, :category, :system_prompt, :ranks, :banner]
```

Add filter function:

```elixir
def filter_by_banner(banner) do
  Enum.filter(all(), &(&1.banner == banner))
end
```

Then tag each member definition. Mapping:
- **Editors** (grammar, tone, style, brevity, technical-writer): `:tech` (except maybe tone-reviewer → could be `:lifestyle`)
- **Analysts**: `:tech` for data/competitive/risk, `:business` for feedback/sentiment
- **Specialists** (frontend, backend, a11y, perf, devops, etc.): all `:tech`
- **Advisors**: `:business` (compliance, scope, brand), `:tech` (security, devils-advocate)
- **Validators**: `:tech`
- **Wildcards**: `:lifestyle` (poet, historian, tabloid, philosopher), `:tech` (nitpicker, intern)
- **Life Use** (life-coach, journal, news, market, sports, science): all `:lifestyle`

Use judgment — the exact mapping matters less than having one. Add `banner: :tech` (or appropriate) to each `%BuiltinMember{}`.

**Step 4: Run tests**

Run: `mix test test/ex_cortex/member_banners_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex/members/member.ex test/ex_cortex/member_banners_test.exs
git commit -m "feat: add banner tags to all builtin members"
```

---

## Task 6: Banner Tags on Library Books

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex/sources/book.ex`

**Step 1: Write the failing test**

Create `/home/andrew/projects/ex_cortex/test/ex_cortex/book_banners_test.exs`:

```elixir
defmodule ExCortex.BookBannersTest do
  use ExUnit.Case, async: true

  alias ExCortex.Sources.Book

  describe "book banners" do
    test "all books have a banner tag" do
      for book <- Book.all() do
        assert book.banner in [:tech, :lifestyle, :business, nil],
               "Book #{book.id} missing banner tag"
      end
    end

    test "filter_by_banner/1 returns matching and nil-banner books" do
      tech = Book.filter_by_banner(:tech)
      assert length(tech) > 0
      assert Enum.all?(tech, &(&1.banner in [:tech, nil]))
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex/book_banners_test.exs`
Expected: Fails — `:banner` not in Book struct or `filter_by_banner` undefined.

**Step 3: Add `:banner` to Book struct and tag books**

In `/home/andrew/projects/ex_cortex/lib/ex_cortex/sources/book.ex`:

The struct already has fields. Add `:banner` with default `nil`:

```elixir
defstruct [:id, :name, :description, :source_type, :default_config, :suggested_guild, :kind, :sandbox, banner: nil]
```

Add filter function (note: `nil` banner books are always included):

```elixir
def filter_by_banner(banner) do
  Enum.filter(all(), &(&1.banner == banner || &1.banner == nil))
end
```

Tag books:
- Generic books (git_repo_watcher, directory_watcher, etc.): `banner: nil` (banner-agnostic)
- Code review / a11y / perf / incident / dependency books: `banner: :tech`
- Contract books: `banner: :business`
- Digest feeds: tag by topic (tech feeds → `:tech`, business → `:business`, sports/culture/science → `:lifestyle`)

**Step 4: Run tests**

Run: `mix test test/ex_cortex/book_banners_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex/sources/book.ex test/ex_cortex/book_banners_test.exs
git commit -m "feat: add banner tags to library books and digest feeds"
```

---

## Task 7: Town Square Banner Picker UI

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/town_square_live.ex`

**Step 1: Write the failing test**

Add to existing town_square_live_test or create a new test:

```elixir
# In test/ex_cortex_web/live/town_square_live_test.exs
describe "banner selection" do
  test "shows banner picker when no banner set", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/town-square")
    assert html =~ "Choose Your Banner"
    assert html =~ "Tech"
    assert html =~ "Lifestyle"
    assert html =~ "Business"
  end

  test "selecting a banner filters guilds", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/town-square")
    html = view |> element(~s{[phx-click="select_banner"][phx-value-banner="tech"]}) |> render_click()
    # Should show tech guilds, not lifestyle ones
    assert html =~ "Code Review"
    refute html =~ "Everyday Council"
  end

  test "banner persists to settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/town-square")
    view |> element(~s{[phx-click="select_banner"][phx-value-banner="tech"]}) |> render_click()
    assert ExCortex.Settings.get_banner() == "tech"
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/ex_cortex_web/live/town_square_live_test.exs`
Expected: Failures — no banner picker UI, no `select_banner` event.

**Step 3: Implement banner picker in TownSquareLive**

Modify `mount/3` in `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/town_square_live.ex`:

```elixir
def mount(_params, _session, socket) do
  banner = Settings.get_banner()
  guilds = build_guild_list()

  filtered_guilds =
    if banner do
      banner_atom = String.to_existing_atom(banner)
      Enum.filter(guilds, fn g -> g.banner == banner_atom end)
    else
      guilds
    end

  {:ok,
   assign(socket,
     banner: banner,
     guilds: guilds,
     filtered_guilds: filtered_guilds,
     confirming: nil
   )}
end
```

Add `handle_event`:

```elixir
def handle_event("select_banner", %{"banner" => banner}, socket) do
  {:ok, _} = Settings.set_banner(banner)
  banner_atom = String.to_existing_atom(banner)
  filtered = Enum.filter(socket.assigns.guilds, fn g -> g.banner == banner_atom end)

  {:noreply,
   socket
   |> assign(banner: banner, filtered_guilds: filtered)
   |> put_flash(:info, "Flying under the #{String.capitalize(banner)} banner!")}
end
```

Update the template to show the banner picker when `@banner == nil`, and show filtered guild cards when banner is set. The banner picker is three large cards:

```heex
<%= if @banner == nil do %>
  <div class="max-w-4xl mx-auto py-12">
    <h1 class="text-2xl font-bold text-center mb-2">Choose Your Banner</h1>
    <p class="text-muted-foreground text-center mb-8">Pick your domain to see relevant guilds, quests, and tools.</p>
    <div class="grid grid-cols-3 gap-6">
      <%= for {name, desc, icon} <- [
        {"tech", "Code review, security audits, incident triage, and developer tooling.", "⚔️"},
        {"lifestyle", "Content curation, creative projects, sports, culture, and science.", "🛡️"},
        {"business", "Contract review, risk assessment, market analysis, and hiring.", "📜"}
      ] do %>
        <button
          phx-click="select_banner"
          phx-value-banner={name}
          class="rounded-lg border-2 border-muted p-6 text-left hover:border-foreground transition-colors"
        >
          <div class="text-3xl mb-3"><%= icon %></div>
          <div class="font-bold text-lg capitalize mb-1"><%= name %></div>
          <div class="text-sm text-muted-foreground"><%= desc %></div>
        </button>
      <% end %>
    </div>
  </div>
<% else %>
  <%!-- Existing guild cards, using @filtered_guilds instead of @guilds --%>
<% end %>
```

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/town_square_live_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/town_square_live.ex test/ex_cortex_web/live/town_square_live_test.exs
git commit -m "feat: banner picker UI on Town Square"
```

---

## Task 8: Banner Indicator in Nav + Nav Simplification

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/components/layouts/root.html.heex`
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/router.ex` (remove `/guide` or keep as-is)

**Step 1: Write the failing test**

Add to an existing layout test or create:

```elixir
# In test/ex_cortex_web/live/layout_test.exs or town_square_live_test.exs
test "nav shows banner indicator when banner is set", %{conn: conn} do
  ExCortex.Settings.set_banner("tech")
  {:ok, _view, html} = live(conn, ~p"/lodge")
  assert html =~ "Tech"
end
```

**Step 2: Run test to verify it fails**

Run the test. Expected: Fails — no banner indicator in nav.

**Step 3: Update the nav in root.html.heex**

In `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/components/layouts/root.html.heex`:

The nav currently iterates over a hardcoded list of 7 items. We need to:

1. Add a banner indicator next to "ExCortex"
2. Reduce to 6 nav items (remove Guide, or convert to icon)

The tricky part: `root.html.heex` uses `@conn`, not LiveView assigns. To get the banner, we need to either:
- Fetch it in a plug and put it in conn assigns, or
- Use a simple helper call

Add a plug to the browser pipeline in router.ex:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {ExCortexWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
  plug :assign_banner
end

defp assign_banner(conn, _opts) do
  assign(conn, :banner, ExCortex.Settings.get_banner())
end
```

Then update the nav:

```heex
<nav class="border-b bg-card sticky top-0 z-50 shadow-sm">
  <div class="max-w-6xl mx-auto flex items-center gap-8 px-6 py-0">
    <a href={~p"/town-square"} class="flex items-center gap-2 shrink-0 py-4 border-b-2 border-transparent hover:opacity-80 transition-opacity">
      <span class="text-sm font-bold text-foreground tracking-widest uppercase select-none">
        ExCortex
      </span>
      <%= if @banner do %>
        <span class="text-xs px-2 py-0.5 rounded-full bg-muted text-muted-foreground font-medium capitalize">
          {@banner}
        </span>
      <% end %>
    </a>
    <div class="flex overflow-x-auto">
      <%= for {label, path} <- [
        {"Lodge", ~p"/lodge"},
        {"Guild Hall", ~p"/guild-hall"},
        {"Quests", ~p"/quests"},
        {"Grimoire", ~p"/grimoire"},
        {"Library", ~p"/library"},
        {"Town Square", ~p"/town-square"}
      ] do %>
        <a
          href={path}
          class={[
            "px-4 py-4 text-sm whitespace-nowrap transition-colors border-b-2",
            if(String.starts_with?(@conn.request_path, path),
              do: "border-foreground text-foreground font-medium",
              else: "border-transparent text-muted-foreground hover:text-foreground hover:border-muted-foreground"
            )
          ]}
        >
          {label}
        </a>
      <% end %>
    </div>
  </div>
</nav>
```

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/town_square_live_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/components/layouts/root.html.heex lib/ex_cortex_web/router.ex
git commit -m "feat: banner indicator in nav, simplify to 6 items"
```

---

## Task 9: Banner Filtering in QuestsLive

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/quests_live.ex`

**Step 1: Write the failing test**

```elixir
# In test/ex_cortex_web/live/quests_live_test.exs
describe "banner filtering" do
  test "quest board filters templates by banner", %{conn: conn} do
    ExCortex.Settings.set_banner("lifestyle")
    {:ok, _view, html} = live(conn, ~p"/quests")
    # Lifestyle templates should appear
    # Tech-only templates should not
    refute html =~ "Jira Ticket Triage"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex_web/live/quests_live_test.exs`
Expected: Fails — all templates still shown.

**Step 3: Filter templates by banner in mount**

In `mount/3` of `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/quests_live.ex`, after building `board_templates`:

```elixir
banner = Settings.get_banner()
banner_atom = if banner, do: String.to_existing_atom(banner), else: nil

board_templates =
  Board.all()
  |> then(fn templates ->
    if banner_atom do
      Enum.filter(templates, &(&1.banner == banner_atom))
    else
      templates
    end
  end)
  |> Enum.map(&board_with_status/1)
```

Add `alias ExCortex.Settings` to the module.

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/quests_live_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/quests_live.ex test/ex_cortex_web/live/quests_live_test.exs
git commit -m "feat: filter quest board templates by active banner"
```

---

## Task 10: Banner Filtering in GuildHallLive and LibraryLive

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/guild_hall_live.ex`
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/library_live.ex`

**Step 1: Write failing tests**

```elixir
# test/ex_cortex_web/live/guild_hall_live_test.exs
describe "banner filtering" do
  test "builtin member catalog filters by banner", %{conn: conn} do
    ExCortex.Settings.set_banner("lifestyle")
    {:ok, _view, html} = live(conn, ~p"/guild-hall")
    # Life Use members should appear, tech specialists should not
    refute html =~ "Frontend Reviewer"
  end
end
```

```elixir
# test/ex_cortex_web/live/library_live_test.exs
describe "banner filtering" do
  test "library books filter by banner", %{conn: conn} do
    ExCortex.Settings.set_banner("lifestyle")
    {:ok, _view, html} = live(conn, ~p"/library")
    # Tech-specific books should be hidden
    refute html =~ "Credo Scanner"
  end
end
```

**Step 2: Run tests to verify they fail**

Run both test files. Expected: Failures.

**Step 3: Add banner filtering to both LiveViews**

In `guild_hall_live.ex` mount, filter the builtin member lists by banner:

```elixir
banner = Settings.get_banner()
banner_atom = if banner, do: String.to_existing_atom(banner), else: nil

builtin_members =
  if banner_atom do
    BuiltinMember.filter_by_banner(banner_atom)
  else
    BuiltinMember.all()
  end
```

Use `builtin_members` instead of calling category functions directly.

In `library_live.ex` mount, filter books:

```elixir
banner = Settings.get_banner()
banner_atom = if banner, do: String.to_existing_atom(banner), else: nil

books =
  if banner_atom do
    Book.filter_by_banner(banner_atom)
  else
    Book.all()
  end
```

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/guild_hall_live_test.exs test/ex_cortex_web/live/library_live_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/guild_hall_live.ex lib/ex_cortex_web/live/library_live.ex test/ex_cortex_web/live/guild_hall_live_test.exs test/ex_cortex_web/live/library_live_test.exs
git commit -m "feat: banner filtering in Guild Hall and Library"
```

---

## Task 11: Redirect to Town Square When No Banner Set

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/lodge_live.ex`
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/router.ex` (possibly add on_mount hook)

**Step 1: Write the failing test**

```elixir
# test/ex_cortex_web/live/lodge_live_test.exs
describe "banner redirect" do
  test "redirects to town square when no banner set", %{conn: conn} do
    # Ensure no banner
    assert ExCortex.Settings.get_banner() == nil
    {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/lodge")
    assert path == "/town-square"
  end

  test "stays on lodge when banner is set", %{conn: conn} do
    ExCortex.Settings.set_banner("tech")
    {:ok, _view, html} = live(conn, ~p"/lodge")
    assert html =~ "Lodge"
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/ex_cortex_web/live/lodge_live_test.exs`
Expected: First test fails — no redirect.

**Step 3: Add banner check to LodgeLive mount**

In `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/lodge_live.ex`:

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) and is_nil(Settings.get_banner()) do
    {:ok, push_navigate(socket, to: ~p"/town-square")}
  else
    # ... existing mount logic
  end
end
```

Add the same pattern to other LiveViews that should require a banner (quests, guild_hall, library, grimoire). Town Square itself should NOT redirect — it's where you pick.

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/lodge_live_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/lodge_live.ex test/ex_cortex_web/live/lodge_live_test.exs
git commit -m "feat: redirect to Town Square when no banner set"
```

---

## Task 12: MDEx Rendering Helper Module

**Files:**
- Create: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/components/markdown.ex`
- Create: `/home/andrew/projects/ex_cortex/test/ex_cortex_web/components/markdown_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule ExCortexWeb.MarkdownTest do
  use ExUnit.Case, async: true

  alias ExCortexWeb.Markdown

  describe "render/1" do
    test "renders markdown to HTML" do
      result = Markdown.render("# Hello")
      assert result =~ "<h1>"
      assert result =~ "Hello"
    end

    test "renders code blocks with syntax highlighting" do
      result = Markdown.render("```elixir\nIO.puts(\"hi\")\n```")
      assert result =~ "IO"
    end

    test "renders emoji shortcodes" do
      result = Markdown.render("Hello :smile:")
      assert result =~ "😄"
    end

    test "handles nil gracefully" do
      assert Markdown.render(nil) == ""
    end

    test "handles empty string" do
      assert Markdown.render("") == ""
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/ex_cortex_web/components/markdown_test.exs`
Expected: Compilation error — module doesn't exist.

**Step 3: Create the Markdown helper module**

Create `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/components/markdown.ex`:

```elixir
defmodule ExCortexWeb.Markdown do
  @moduledoc "MDEx-powered Markdown rendering helpers."

  def render(nil), do: ""
  def render(""), do: ""

  def render(markdown) when is_binary(markdown) do
    MDEx.to_html!(markdown, extension: [shortcodes: true, table: true, tasklist: true, alerts: true, strikethrough: true])
  end
end
```

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/components/markdown_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/components/markdown.ex test/ex_cortex_web/components/markdown_test.exs
git commit -m "feat: add Markdown rendering helper using MDEx"
```

---

## Task 13: MDEx Component for LiveView Templates

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/components/core_components.ex`

**Step 1: Write the failing test**

```elixir
# test/ex_cortex_web/components/markdown_component_test.exs
defmodule ExCortexWeb.MarkdownComponentTest do
  use ExCortexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component

  describe "md/1 component" do
    test "renders markdown content" do
      assigns = %{content: "**bold text**"}
      html = rendered_to_string(~H"""
      <ExCortexWeb.CoreComponents.md content={@content} />
      """)
      assert html =~ "<strong>"
      assert html =~ "bold text"
    end

    test "renders nil as empty" do
      assigns = %{content: nil}
      html = rendered_to_string(~H"""
      <ExCortexWeb.CoreComponents.md content={@content} />
      """)
      assert html =~ ""
    end
  end
end
```

**Step 2: Run test to verify it fails**

Expected: Function `md/1` undefined.

**Step 3: Add the `md` component to CoreComponents**

In `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/components/core_components.ex`:

```elixir
attr :content, :string, default: nil
attr :class, :string, default: "prose prose-sm dark:prose-invert max-w-none"

def md(assigns) do
  ~H"""
  <div class={@class}>
    <%= if @content do %>
      <%= Phoenix.HTML.raw(ExCortexWeb.Markdown.render(@content)) %>
    <% end %>
  </div>
  """
end
```

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/components/markdown_component_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/components/core_components.ex test/ex_cortex_web/components/markdown_component_test.exs
git commit -m "feat: add <.md> component for inline Markdown rendering"
```

---

## Task 14: Wire MDEx Rendering Into Grimoire

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/grimoire_live.ex`

**Step 1: Write the failing test**

```elixir
# In test/ex_cortex_web/live/grimoire_live_test.exs
describe "markdown rendering" do
  test "grimoire entries render markdown", %{conn: conn} do
    # Create a lore entry with markdown content
    ExCortex.Lore.create_entry(%{
      content: "# Test Entry\n\n**Bold** text with `code`",
      tags: ["test"],
      source: "test"
    })

    {:ok, _view, html} = live(conn, ~p"/grimoire")
    assert html =~ "<strong>Bold</strong>"
  end
end
```

**Step 2: Run test to verify it fails**

Expected: Fails — content rendered as plain text.

**Step 3: Replace raw text rendering with `<.md>` component**

In the grimoire template, wherever lore entry content is displayed, replace the plain text output with:

```heex
<.md content={entry.content} />
```

instead of:

```heex
<p class="..."><%= entry.content %></p>
```

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/grimoire_live_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/grimoire_live.ex test/ex_cortex_web/live/grimoire_live_test.exs
git commit -m "feat: render grimoire entries with MDEx markdown"
```

---

## Task 15: Wire MDEx Into Guild Hall (Charters + System Prompts)

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/guild_hall_live.ex`

**Step 1: Write the failing test**

```elixir
# In test/ex_cortex_web/live/guild_hall_live_test.exs
describe "markdown rendering" do
  test "member system prompts render as markdown in expanded view", %{conn: conn} do
    # Create a member with markdown in system prompt
    %Excellence.Schemas.Member{}
    |> Excellence.Schemas.Member.changeset(%{
      type: "role",
      name: "Test MD Member",
      status: "active",
      config: %{"system_prompt" => "# Reviewer\n\nYou check **code quality**."}
    })
    |> ExCortex.Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/guild-hall")
    # Expand the member card to see system prompt
    html = view |> element(~s{[phx-click="toggle_expand"][phx-value-id]}) |> render_click()
    assert html =~ "<strong>code quality</strong>"
  end
end
```

**Step 2: Run test to verify it fails**

Expected: System prompt shown as plain text.

**Step 3: Replace system prompt display with `<.md>` component**

Find where `config["system_prompt"]` is displayed in the member expanded view and replace with:

```heex
<.md content={member.config["system_prompt"]} />
```

Do the same for guild charter text display.

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/guild_hall_live_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/guild_hall_live.ex test/ex_cortex_web/live/guild_hall_live_test.exs
git commit -m "feat: render charters and system prompts with MDEx"
```

---

## Task 16: Quest Card Redesign — Collapsible Steps

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/quests_live.ex`

**Step 1: Write the failing test**

```elixir
# In test/ex_cortex_web/live/quests_live_test.exs
describe "quest card redesign" do
  test "quest template shows step count in collapsed state", %{conn: conn} do
    ExCortex.Settings.set_banner("tech")
    {:ok, _view, html} = live(conn, ~p"/quests")
    # Templates with steps should show step count
    assert html =~ ~r/\d+ steps?/
  end

  test "expanding a template shows nested step cards", %{conn: conn} do
    ExCortex.Settings.set_banner("tech")
    {:ok, view, _html} = live(conn, ~p"/quests")
    # Click to expand a template
    html = view |> element(~s{[phx-click="board_expand_template"]}, ~r/./) |> render_click()
    assert html =~ "step-card"
  end
end
```

**Step 2: Run tests to verify they fail**

Expected: No step count shown, no expand behavior on templates.

**Step 3: Add expand/collapse to template cards**

In `quests_live.ex`, add to assigns:

```elixir
board_expanded: MapSet.new()
```

Add event handler:

```elixir
def handle_event("board_expand_template", %{"id" => id}, socket) do
  expanded = socket.assigns.board_expanded
  new_expanded = if MapSet.member?(expanded, id), do: MapSet.delete(expanded, id), else: MapSet.put(expanded, id)
  {:noreply, assign(socket, board_expanded: new_expanded)}
end
```

Update the template card rendering to show:

**Collapsed:**
```heex
<div class="border rounded-lg p-4 cursor-pointer" phx-click="board_expand_template" phx-value-id={template.id}>
  <div class="flex items-center justify-between">
    <div>
      <span class="font-medium">{template.name}</span>
      <span class="ml-2 text-xs text-muted-foreground">{length(template.step_definitions)} steps</span>
    </div>
    <div class="flex items-center gap-2">
      <span class={["text-xs px-2 py-0.5 rounded-full", readiness_class(template.readiness)]}>
        {readiness_label(template)}
      </span>
      <.button phx-click="board_recruit_and_go" phx-value-id={template.id} size="sm">
        Recruit & Go
      </.button>
      <.button variant="outline" phx-click="board_expand_template" phx-value-id={template.id} size="sm">
        Customize
      </.button>
    </div>
  </div>
  <.md content={template.description} class="text-sm text-muted-foreground mt-1" />
</div>
```

**Expanded (inside the same card, conditionally):**
```heex
<%= if MapSet.member?(@board_expanded, template.id) do %>
  <div class="mt-4 space-y-2">
    <%= for {step_def, idx} <- Enum.with_index(template.step_definitions) do %>
      <div class="step-card border rounded p-3 ml-4 bg-muted/30">
        <div class="font-medium text-sm">{step_def.name}</div>
        <.md content={step_def.description} class="text-xs text-muted-foreground mt-1" />
        <%= if step_def[:lore_tags] && step_def.lore_tags != [] do %>
          <div class="text-xs mt-1">
            <span class="text-muted-foreground">Tags:</span>
            <%= for tag <- step_def.lore_tags do %>
              <span class="ml-1 px-1.5 py-0.5 bg-muted rounded text-xs">{tag}</span>
            <% end %>
          </div>
        <% end %>
      </div>
    <% end %>
  </div>
  <div class="mt-4 flex justify-end">
    <.button phx-click="board_recruit_and_go" phx-value-id={template.id}>
      Install
    </.button>
  </div>
<% end %>
```

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/quests_live_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/quests_live.ex test/ex_cortex_web/live/quests_live_test.exs
git commit -m "feat: collapsible step cards in quest board templates"
```

---

## Task 17: "Recruit & Go" Turnkey Install Path

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex/board.ex`
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/quests_live.ex`

**Step 1: Write the failing test**

```elixir
# test/ex_cortex/board_recruit_and_go_test.exs
defmodule ExCortex.Board.RecruitAndGoTest do
  use ExCortex.DataCase

  alias ExCortex.Board

  describe "recruit_and_go/1" do
    test "installs quest, steps, and auto-recruits missing members" do
      template = Board.get("jira_ticket_triage")
      assert template != nil

      {:ok, result} = Board.recruit_and_go(template)
      assert result.quest
      assert length(result.steps_created) > 0

      # Members should have been auto-recruited
      members = ExCortex.Repo.all(Excellence.Schemas.Member)
      assert length(members) > 0
    end
  end
end
```

**Step 2: Run test to verify it fails**

Expected: `recruit_and_go/1` undefined.

**Step 3: Implement `Board.recruit_and_go/1`**

In `/home/andrew/projects/ex_cortex/lib/ex_cortex/board.ex`:

```elixir
def recruit_and_go(%__MODULE__{} = template) do
  # 1. Install quest + steps (existing logic)
  case install(template) do
    {:ok, quest} ->
      # 2. Auto-recruit missing members from suggested_team
      recruited = auto_recruit_members(template)
      {:ok, %{quest: quest, steps_created: template.step_definitions, members_recruited: recruited}}

    error ->
      error
  end
end

defp auto_recruit_members(%{suggested_team: nil}), do: []
defp auto_recruit_members(%{suggested_team: team_desc}) do
  # Parse suggested_team to find member archetypes
  # Look at existing members, recruit any that are missing
  existing = ExCortex.Repo.all(Excellence.Schemas.Member) |> Enum.map(& &1.name)

  ExCortex.Members.BuiltinMember.all()
  |> Enum.filter(fn m ->
    String.contains?(String.downcase(team_desc), String.downcase(m.name)) and
      m.name not in existing
  end)
  |> Enum.map(fn member ->
    rank_config = member.ranks[:journeyman] || member.ranks[:apprentice]

    %Excellence.Schemas.Member{}
    |> Excellence.Schemas.Member.changeset(%{
      type: "role",
      name: member.name,
      status: "active",
      source: "db",
      team: to_string(member.category),
      config: %{
        "member_id" => member.id,
        "system_prompt" => member.system_prompt,
        "rank" => "journeyman",
        "model" => rank_config.model,
        "strategy" => rank_config.strategy
      }
    })
    |> ExCortex.Repo.insert(on_conflict: :nothing)

    member.name
  end)
end
```

**Step 4: Wire into QuestsLive**

In `quests_live.ex`, add event handler:

```elixir
def handle_event("board_recruit_and_go", %{"id" => id}, socket) do
  case Board.get(id) do
    nil ->
      {:noreply, put_flash(socket, :error, "Template not found")}

    template ->
      case Board.recruit_and_go(template) do
        {:ok, result} ->
          msg =
            case result.members_recruited do
              [] -> "\"#{template.name}\" installed!"
              names -> "\"#{template.name}\" installed! Recruited: #{Enum.join(names, ", ")}"
            end

          {:noreply,
           socket
           |> assign(
             board_installed: MapSet.put(socket.assigns.board_installed, id),
             board_installing: nil,
             steps: Quests.list_steps(),
             quests: Quests.list_quests()
           )
           |> put_flash(:info, msg)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Install failed: #{inspect(reason)}")}
      end
  end
end
```

**Step 5: Run tests**

Run: `mix test test/ex_cortex/board_recruit_and_go_test.exs`
Expected: Pass.

**Step 6: Commit**

```bash
git add lib/ex_cortex/board.ex lib/ex_cortex_web/live/quests_live.ex test/ex_cortex/board_recruit_and_go_test.exs
git commit -m "feat: Recruit & Go turnkey install with auto member recruitment"
```

---

## Task 18: Quest Board "Customize" Path Redesign

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/quests_live.ex`

**Step 1: Write the failing test**

```elixir
# In test/ex_cortex_web/live/quests_live_test.exs
describe "customize path" do
  test "customize expands template with editable step cards", %{conn: conn} do
    ExCortex.Settings.set_banner("tech")
    {:ok, view, _html} = live(conn, ~p"/quests")
    # Click customize on a template
    html = view |> element(~s{[phx-click="board_expand_template"]}, ~r/./) |> render_click()
    # Should see step cards with remove buttons
    assert html =~ "step-card"
  end
end
```

**Step 2: Run test — may already pass from Task 16**

If it passes, this task is about adding the editable features: reorder and remove buttons on step cards within the expanded template.

**Step 3: Add editable step controls in expanded template view**

When a template is expanded, each step card gets:

```heex
<div class="step-card border rounded p-3 ml-4 bg-muted/30 flex items-start justify-between">
  <div class="flex-1">
    <div class="font-medium text-sm">{step_def.name}</div>
    <.md content={step_def[:description]} class="text-xs text-muted-foreground mt-1" />
  </div>
  <div class="flex items-center gap-1 ml-2">
    <button
      :if={idx > 0}
      phx-click="board_move_step"
      phx-value-template-id={template.id}
      phx-value-index={idx}
      phx-value-direction="up"
      class="text-xs text-muted-foreground hover:text-foreground"
    >↑</button>
    <button
      :if={idx < length(template.step_definitions) - 1}
      phx-click="board_move_step"
      phx-value-template-id={template.id}
      phx-value-index={idx}
      phx-value-direction="down"
      class="text-xs text-muted-foreground hover:text-foreground"
    >↓</button>
    <button
      phx-click="board_remove_step"
      phx-value-template-id={template.id}
      phx-value-index={idx}
      class="text-xs text-destructive hover:text-destructive/80 ml-1"
    >✕</button>
  </div>
</div>
```

Add event handlers for customizing a template in-memory before install:

```elixir
# Store customized templates in assigns
def handle_event("board_move_step", %{"template-id" => id, "index" => idx_str, "direction" => dir}, socket) do
  idx = String.to_integer(idx_str)
  customized = Map.get(socket.assigns, :board_customized, %{})
  template = get_working_template(socket, id)
  steps = template.step_definitions

  new_idx = if dir == "up", do: idx - 1, else: idx + 1
  swapped = steps |> List.replace_at(idx, Enum.at(steps, new_idx)) |> List.replace_at(new_idx, Enum.at(steps, idx))

  customized = Map.put(customized, id, %{template | step_definitions: swapped})
  {:noreply, assign(socket, board_customized: customized)}
end

def handle_event("board_remove_step", %{"template-id" => id, "index" => idx_str}, socket) do
  idx = String.to_integer(idx_str)
  customized = Map.get(socket.assigns, :board_customized, %{})
  template = get_working_template(socket, id)
  steps = List.delete_at(template.step_definitions, idx)

  customized = Map.put(customized, id, %{template | step_definitions: steps})
  {:noreply, assign(socket, board_customized: customized)}
end

defp get_working_template(socket, id) do
  case Map.get(socket.assigns[:board_customized] || %{}, id) do
    nil -> Enum.find(socket.assigns.board_templates, &(&1.id == id))
    custom -> custom
  end
end
```

Add `board_customized: %{}` to mount assigns.

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/quests_live_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/quests_live.ex test/ex_cortex_web/live/quests_live_test.exs
git commit -m "feat: editable step cards in customize path"
```

---

## Task 19: MDEx Rendering in Quest Descriptions and Step Cards

**Files:**
- Modify: `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/quests_live.ex`

**Step 1: Write the failing test**

```elixir
# In test/ex_cortex_web/live/quests_live_test.exs
describe "markdown in quest descriptions" do
  test "active quest descriptions render markdown", %{conn: conn} do
    ExCortex.Settings.set_banner("tech")
    ExCortex.Quests.create_step(%{name: "MD Step", description: "**bold step**", status: "active", trigger: "manual"})
    {:ok, step} = ExCortex.Quests.create_step(%{name: "MD Step 2", description: "test", status: "active", trigger: "manual"})
    ExCortex.Quests.create_quest(%{
      name: "MD Quest",
      description: "# Quest Title\n\nWith **markdown**",
      trigger: "manual",
      steps: [%{"step_id" => step.id, "flow" => "always"}]
    })

    {:ok, view, _html} = live(conn, ~p"/quests")
    html = view |> element(~s{[phx-click="toggle_expand"]}, "MD Quest") |> render_click()
    assert html =~ "<strong>markdown</strong>"
  end
end
```

**Step 2: Run test to verify it fails**

Expected: Description rendered as plain text.

**Step 3: Replace quest/step description rendering with `<.md>`**

In the quests template, find where `quest.description` and step descriptions are rendered. Replace plain text output with `<.md content={...} />`.

For active quests in the expanded card:
```heex
<.md content={quest.description} />
```

For step descriptions in active quests:
```heex
<.md content={step.description} class="text-xs text-muted-foreground" />
```

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/live/quests_live_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/live/quests_live.ex test/ex_cortex_web/live/quests_live_test.exs
git commit -m "feat: render quest and step descriptions with MDEx"
```

---

## Task 20: Run Full Test Suite and Fix Breakage

**Step 1: Run full test suite**

Run: `mix test`

**Step 2: Fix any broken tests**

Common issues to expect:
- Existing tests that assert on raw text content may now find HTML-wrapped content
- Snapshot-based accessibility tests may need regeneration
- Tests that check for specific strings in rendered HTML may need updating

**Step 3: Run format**

Run: `mix format`

**Step 4: Run full suite again**

Run: `mix test`
Expected: All green.

**Step 5: Commit**

```bash
git add -A
git commit -m "fix: update tests for banner filtering and MDEx rendering"
```

---

## Summary

| Task | What | Key Files |
|------|------|-----------|
| 1 | Add MDEx dep | mix.exs |
| 2 | Settings schema + context | settings.ex, migration |
| 3 | Banner tags on charters | charters/*.ex |
| 4 | Banner tags on board templates | board.ex, board/*.ex |
| 5 | Banner tags on builtin members | members/member.ex |
| 6 | Banner tags on library books | sources/book.ex |
| 7 | Town Square banner picker UI | town_square_live.ex |
| 8 | Nav banner indicator | root.html.heex, router.ex |
| 9 | Banner filtering in QuestsLive | quests_live.ex |
| 10 | Banner filtering in GuildHall + Library | guild_hall_live.ex, library_live.ex |
| 11 | Redirect when no banner | lodge_live.ex |
| 12 | MDEx rendering helper | markdown.ex |
| 13 | `<.md>` LiveView component | core_components.ex |
| 14 | MDEx in Grimoire | grimoire_live.ex |
| 15 | MDEx in Guild Hall | guild_hall_live.ex |
| 16 | Collapsible step cards | quests_live.ex |
| 17 | Recruit & Go install path | board.ex, quests_live.ex |
| 18 | Customize path with editable steps | quests_live.ex |
| 19 | MDEx in quest descriptions | quests_live.ex |
| 20 | Full suite fix-up | various |
