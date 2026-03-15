# Lodge & Grimoire Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the Lodge from a monitoring dashboard into an active workspace with typed cards, rebuild the Grimoire as a quest log with per-quest telemetry, and absorb ex_cellence_ui components into ExCortexUI.

**Architecture:** New `lodge_cards` table stores typed cards (note, checklist, meeting, alert, link, proposal, augury) with jsonb metadata. Lodge LiveView renders cards via pattern-matched function components. Grimoire gets two-level navigation (overview + per-quest drill-down) housing the relocated monitoring widgets. Ex_cellence_ui components move into `lib/ex_cortex_ui/` under the `ExCortexUI` namespace.

**Tech Stack:** Phoenix LiveView, Ecto, SaladUI components, MDEx markdown rendering, PubSub for live updates.

---

## Task 1: Absorb ex_cellence_ui into ExCortexUI

**Files:**
- Create: `lib/ex_cortex_ui/components/role_form.ex`
- Create: `lib/ex_cortex_ui/components/actions_form.ex`
- Create: `lib/ex_cortex_ui/components/guard_form.ex`
- Create: `lib/ex_cortex_ui/components/pipeline_builder.ex`
- Create: `lib/ex_cortex_ui/components/charter_picker.ex`
- Create: `lib/ex_cortex_ui/components/ai_builder.ex`
- Modify: `mix.exs` (remove `:ex_cellence_ui` dep)

**Step 1: Create the ExCortexUI directory and copy components**

Create `lib/ex_cortex_ui/components/`. For each component file in `ex_cellence_ui/lib/ex_cellence_ui/components/`, copy it to the new location and rename the module from `ExCellenceUI.Components.*` to `ExCortexUI.Components.*`.

Example for `role_form.ex`:
```elixir
defmodule ExCortexUI.Components.RoleForm do
  # ... same implementation, just renamed module
end
```

Do this for all 6 component files:
- `role_form.ex` → `ExCortexUI.Components.RoleForm`
- `actions_form.ex` → `ExCortexUI.Components.ActionsForm`
- `guard_form.ex` → `ExCortexUI.Components.GuardForm`
- `pipeline_builder.ex` → `ExCortexUI.Components.PipelineBuilder`
- `charter_picker.ex` → `ExCortexUI.Components.CharterPicker`
- `ai_builder.ex` → `ExCortexUI.Components.AIBuilder`

**Step 2: Remove ex_cellence_ui path dep from mix.exs**

In `/home/andrew/projects/ex_cortex/mix.exs`, remove:
```elixir
{:ex_cellence_ui, path: "ex_cellence_ui"},
```

**Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles cleanly. No code references ExCellenceUI anywhere in the main app.

**Step 4: Commit**

```bash
git add lib/ex_cortex_ui/ mix.exs
git commit -m "feat: absorb ex_cellence_ui components into ExCortexUI namespace"
```

---

## Task 2: Lodge Cards Schema and Migration

**Files:**
- Create: `lib/ex_cortex/lodge/card.ex`
- Create: `priv/repo/migrations/*_create_lodge_cards.exs`

**Step 1: Write the failing test**

Create `test/ex_cortex/lodge/card_test.exs`:

```elixir
defmodule ExCortex.Lodge.CardTest do
  use ExCortex.DataCase

  alias ExCortex.Lodge.Card

  describe "changeset/2" do
    test "valid note card" do
      attrs = %{type: "note", title: "Test", body: "hello", status: "active", source: "manual"}
      changeset = Card.changeset(%Card{}, attrs)
      assert changeset.valid?
    end

    test "valid checklist card with metadata" do
      attrs = %{
        type: "checklist",
        title: "TODO",
        metadata: %{"items" => [%{"text" => "Buy milk", "checked" => false}]},
        status: "active",
        source: "manual"
      }
      changeset = Card.changeset(%Card{}, attrs)
      assert changeset.valid?
    end

    test "rejects invalid type" do
      attrs = %{type: "invalid", title: "Test", status: "active", source: "manual"}
      changeset = Card.changeset(%Card{}, attrs)
      refute changeset.valid?
    end

    test "rejects invalid status" do
      attrs = %{type: "note", title: "Test", status: "bogus", source: "manual"}
      changeset = Card.changeset(%Card{}, attrs)
      refute changeset.valid?
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex/lodge/card_test.exs`
Expected: Compilation error — `ExCortex.Lodge.Card` not found.

**Step 3: Create the migration**

Run: `mix ecto.gen.migration create_lodge_cards`

Edit the migration:

```elixir
defmodule ExCortex.Repo.Migrations.CreateLodgeCards do
  use Ecto.Migration

  def change do
    create table(:lodge_cards) do
      add :type, :string, null: false
      add :title, :string, null: false
      add :body, :text, default: ""
      add :metadata, :map, default: %{}
      add :pinned, :boolean, default: false, null: false
      add :source, :string, null: false
      add :quest_id, :integer
      add :status, :string, default: "active", null: false

      timestamps()
    end

    create index(:lodge_cards, [:type])
    create index(:lodge_cards, [:status])
    create index(:lodge_cards, [:quest_id])
    create index(:lodge_cards, [:pinned])
  end
end
```

**Step 4: Create the schema module**

Create `lib/ex_cortex/lodge/card.ex`:

```elixir
defmodule ExCortex.Lodge.Card do
  use Ecto.Schema

  import Ecto.Changeset

  @valid_types ~w(note checklist meeting alert link proposal augury)
  @valid_statuses ~w(active dismissed archived)

  schema "lodge_cards" do
    field :type, :string
    field :title, :string
    field :body, :string, default: ""
    field :metadata, :map, default: %{}
    field :pinned, :boolean, default: false
    field :source, :string
    field :quest_id, :integer
    field :status, :string, default: "active"

    timestamps()
  end

  def changeset(card, attrs) do
    card
    |> cast(attrs, [:type, :title, :body, :metadata, :pinned, :source, :quest_id, :status])
    |> validate_required([:type, :title, :source, :status])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
  end
end
```

**Step 5: Run migration and tests**

Run: `mix ecto.migrate && mix test test/ex_cortex/lodge/card_test.exs`
Expected: All 4 tests pass.

**Step 6: Commit**

```bash
git add lib/ex_cortex/lodge/card.ex test/ex_cortex/lodge/card_test.exs priv/repo/migrations/*_create_lodge_cards.exs
git commit -m "feat: add lodge_cards schema and migration"
```

---

## Task 3: Lodge Context Module

**Files:**
- Create: `lib/ex_cortex/lodge.ex`
- Create: `test/ex_cortex/lodge_test.exs`

**Step 1: Write the failing test**

Create `test/ex_cortex/lodge_test.exs`:

```elixir
defmodule ExCortex.LodgeTest do
  use ExCortex.DataCase

  alias ExCortex.Lodge

  describe "list_cards/1" do
    test "returns active cards ordered by pinned desc, inserted_at desc" do
      {:ok, pinned} = Lodge.create_card(%{type: "note", title: "Pinned", source: "manual", pinned: true})
      {:ok, recent} = Lodge.create_card(%{type: "note", title: "Recent", source: "manual"})
      {:ok, _dismissed} = Lodge.create_card(%{type: "note", title: "Gone", source: "manual", status: "dismissed"})

      cards = Lodge.list_cards()
      assert length(cards) == 2
      assert hd(cards).id == pinned.id
    end

    test "filters by type" do
      {:ok, _} = Lodge.create_card(%{type: "note", title: "A", source: "manual"})
      {:ok, _} = Lodge.create_card(%{type: "alert", title: "B", source: "manual"})

      cards = Lodge.list_cards(type: "note")
      assert length(cards) == 1
      assert hd(cards).type == "note"
    end
  end

  describe "create_card/1" do
    test "creates a card" do
      {:ok, card} = Lodge.create_card(%{type: "note", title: "Hello", body: "world", source: "manual"})
      assert card.id
      assert card.type == "note"
      assert card.status == "active"
    end
  end

  describe "update_card/2" do
    test "updates a card" do
      {:ok, card} = Lodge.create_card(%{type: "note", title: "Old", source: "manual"})
      {:ok, updated} = Lodge.update_card(card, %{title: "New"})
      assert updated.title == "New"
    end
  end

  describe "dismiss_card/1" do
    test "sets status to dismissed" do
      {:ok, card} = Lodge.create_card(%{type: "note", title: "Bye", source: "manual"})
      {:ok, dismissed} = Lodge.dismiss_card(card)
      assert dismissed.status == "dismissed"
    end
  end

  describe "toggle_pin/1" do
    test "toggles pinned state" do
      {:ok, card} = Lodge.create_card(%{type: "note", title: "Pin me", source: "manual"})
      refute card.pinned
      {:ok, pinned} = Lodge.toggle_pin(card)
      assert pinned.pinned
      {:ok, unpinned} = Lodge.toggle_pin(pinned)
      refute unpinned.pinned
    end
  end

  describe "post_card/1" do
    test "creates a card and broadcasts" do
      Phoenix.PubSub.subscribe(ExCortex.PubSub, "lodge")
      {:ok, card} = Lodge.post_card(%{type: "alert", title: "Urgent", source: "quest"})
      assert card.id
      assert_receive {:lodge_card_posted, ^card}
    end
  end

  describe "toggle_checklist_item/3" do
    test "toggles a checklist item" do
      {:ok, card} = Lodge.create_card(%{
        type: "checklist",
        title: "TODO",
        source: "manual",
        metadata: %{"items" => [%{"text" => "A", "checked" => false}, %{"text" => "B", "checked" => true}]}
      })

      {:ok, updated} = Lodge.toggle_checklist_item(card, 0)
      assert Enum.at(updated.metadata["items"], 0)["checked"] == true
      assert Enum.at(updated.metadata["items"], 1)["checked"] == true
    end
  end

  describe "delete_card/1" do
    test "deletes a card" do
      {:ok, card} = Lodge.create_card(%{type: "note", title: "Delete me", source: "manual"})
      {:ok, _} = Lodge.delete_card(card)
      assert Lodge.list_cards() == []
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex/lodge_test.exs`
Expected: Compilation error — `ExCortex.Lodge` not found.

**Step 3: Create the Lodge context**

Create `lib/ex_cortex/lodge.ex`:

```elixir
defmodule ExCortex.Lodge do
  @moduledoc "Context for Lodge workspace cards."

  import Ecto.Query

  alias ExCortex.Lodge.Card
  alias ExCortex.Repo

  def list_cards(opts \\ []) do
    query =
      from(c in Card,
        where: c.status == "active",
        order_by: [desc: c.pinned, desc: c.inserted_at]
      )

    query =
      case Keyword.get(opts, :type) do
        nil -> query
        type -> where(query, [c], c.type == ^type)
      end

    Repo.all(query)
  end

  def get_card!(id), do: Repo.get!(Card, id)

  def create_card(attrs) do
    %Card{} |> Card.changeset(attrs) |> Repo.insert()
  end

  def update_card(%Card{} = card, attrs) do
    card |> Card.changeset(attrs) |> Repo.update()
  end

  def dismiss_card(%Card{} = card) do
    update_card(card, %{status: "dismissed"})
  end

  def toggle_pin(%Card{} = card) do
    update_card(card, %{pinned: !card.pinned})
  end

  def delete_card(%Card{} = card) do
    Repo.delete(card)
  end

  def post_card(attrs) do
    case create_card(attrs) do
      {:ok, card} ->
        Phoenix.PubSub.broadcast(ExCortex.PubSub, "lodge", {:lodge_card_posted, card})
        {:ok, card}

      error ->
        error
    end
  end

  def toggle_checklist_item(%Card{type: "checklist"} = card, index) do
    items = card.metadata["items"] || []

    updated_items =
      List.update_at(items, index, fn item ->
        Map.put(item, "checked", !item["checked"])
      end)

    update_card(card, %{metadata: Map.put(card.metadata, "items", updated_items)})
  end
end
```

**Step 4: Run tests**

Run: `mix test test/ex_cortex/lodge_test.exs`
Expected: All 9 tests pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex/lodge.ex test/ex_cortex/lodge_test.exs
git commit -m "feat: add Lodge context for card CRUD and PubSub"
```

---

## Task 4: Lodge Card Renderer Components

**Files:**
- Create: `lib/ex_cortex_web/components/lodge_cards.ex`
- Create: `test/ex_cortex_web/components/lodge_cards_test.exs`

**Step 1: Write the failing test**

Create `test/ex_cortex_web/components/lodge_cards_test.exs`:

```elixir
defmodule ExCortexWeb.LodgeCardsTest do
  use ExCortexWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias ExCortexWeb.Components.LodgeCards

  defp render_card(card) do
    assigns = %{card: card}
    rendered_to_string(~H"<LodgeCards.lodge_card card={@card} />")
  end

  describe "lodge_card/1" do
    test "renders note card" do
      card = %{type: "note", title: "My Note", body: "**hello**", pinned: false, metadata: %{}, id: 1, status: "active"}
      html = render_card(card)
      assert html =~ "My Note"
      assert html =~ "<strong>hello</strong>"
    end

    test "renders checklist card with items" do
      card = %{
        type: "checklist",
        title: "TODO",
        body: "",
        pinned: false,
        id: 2,
        status: "active",
        metadata: %{"items" => [%{"text" => "Buy milk", "checked" => false}, %{"text" => "Done", "checked" => true}]}
      }
      html = render_card(card)
      assert html =~ "TODO"
      assert html =~ "Buy milk"
      assert html =~ "Done"
    end

    test "renders alert card with distinct styling" do
      card = %{type: "alert", title: "Warning!", body: "Disk full", pinned: false, metadata: %{}, id: 3, status: "active"}
      html = render_card(card)
      assert html =~ "Warning!"
      assert html =~ "border-destructive"
    end

    test "renders link card" do
      card = %{type: "link", title: "Docs", body: "Reference", pinned: false, metadata: %{"url" => "https://example.com"}, id: 4, status: "active"}
      html = render_card(card)
      assert html =~ "Docs"
      assert html =~ "https://example.com"
    end

    test "renders proposal card with actions" do
      card = %{
        type: "proposal",
        title: "Change roster",
        body: "Narrow to masters",
        pinned: false,
        id: 5,
        status: "active",
        metadata: %{"proposal_type" => "roster_change", "proposal_id" => 42}
      }
      html = render_card(card)
      assert html =~ "Change roster"
      assert html =~ "Approve"
      assert html =~ "Reject"
    end

    test "renders meeting card" do
      card = %{
        type: "meeting",
        title: "Standup",
        body: "Daily sync",
        pinned: false,
        id: 6,
        status: "active",
        metadata: %{"attendees" => ["Alice", "Bob"], "agenda" => ["Status", "Blockers"]}
      }
      html = render_card(card)
      assert html =~ "Standup"
      assert html =~ "Alice"
    end

    test "shows pin indicator" do
      card = %{type: "note", title: "Pinned", body: "", pinned: true, metadata: %{}, id: 7, status: "active"}
      html = render_card(card)
      assert html =~ "pinned"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_cortex_web/components/lodge_cards_test.exs`
Expected: Compilation error — `ExCortexWeb.Components.LodgeCards` not found.

**Step 3: Create the card renderer module**

Create `lib/ex_cortex_web/components/lodge_cards.ex`:

```elixir
defmodule ExCortexWeb.Components.LodgeCards do
  @moduledoc "Function components for rendering Lodge cards by type."
  use Phoenix.Component

  import SaladUI.Badge
  import SaladUI.Button

  attr :card, :map, required: true

  def lodge_card(%{card: %{type: "note"}} = assigns) do
    ~H"""
    <.card_wrapper card={@card}>
      <.md_body body={@card.body} />
    </.card_wrapper>
    """
  end

  def lodge_card(%{card: %{type: "checklist"}} = assigns) do
    items = assigns.card.metadata["items"] || []
    assigns = assign(assigns, :items, items)

    ~H"""
    <.card_wrapper card={@card}>
      <div class="space-y-1.5">
        <%= for {item, idx} <- Enum.with_index(@items) do %>
          <label class="flex items-center gap-2 text-sm cursor-pointer">
            <input
              type="checkbox"
              checked={item["checked"]}
              phx-click="toggle_checklist_item"
              phx-value-card-id={@card.id}
              phx-value-index={idx}
              class="rounded border-input"
            />
            <span class={if item["checked"], do: "line-through text-muted-foreground"}>{item["text"]}</span>
          </label>
        <% end %>
      </div>
    </.card_wrapper>
    """
  end

  def lodge_card(%{card: %{type: "meeting"}} = assigns) do
    attendees = assigns.card.metadata["attendees"] || []
    agenda = assigns.card.metadata["agenda"] || []
    assigns = assign(assigns, attendees: attendees, agenda: agenda)

    ~H"""
    <.card_wrapper card={@card}>
      <.md_body body={@card.body} />
      <%= if @attendees != [] do %>
        <div class="flex flex-wrap gap-1 mt-2">
          <%= for a <- @attendees do %>
            <.badge variant="outline" class="text-xs">{a}</.badge>
          <% end %>
        </div>
      <% end %>
      <%= if @agenda != [] do %>
        <ul class="text-sm text-muted-foreground mt-2 list-disc pl-4">
          <%= for item <- @agenda do %>
            <li>{item}</li>
          <% end %>
        </ul>
      <% end %>
    </.card_wrapper>
    """
  end

  def lodge_card(%{card: %{type: "alert"}} = assigns) do
    ~H"""
    <div class="rounded-lg border-2 border-destructive/50 bg-destructive/5 p-5 space-y-2">
      <.card_header card={@card} />
      <.md_body body={@card.body} />
      <.card_actions card={@card} />
    </div>
    """
  end

  def lodge_card(%{card: %{type: "link"}} = assigns) do
    url = assigns.card.metadata["url"] || ""
    assigns = assign(assigns, :url, url)

    ~H"""
    <.card_wrapper card={@card}>
      <.md_body body={@card.body} />
      <%= if @url != "" do %>
        <a href={@url} target="_blank" rel="noopener" class="text-sm text-primary hover:underline truncate block mt-1">
          {@url}
        </a>
      <% end %>
    </.card_wrapper>
    """
  end

  def lodge_card(%{card: %{type: "proposal"}} = assigns) do
    ~H"""
    <.card_wrapper card={@card}>
      <.md_body body={@card.body} />
      <div class="flex gap-2 mt-3">
        <.button size="sm" variant="outline" phx-click="approve_proposal" phx-value-card-id={@card.id}>
          Approve
        </.button>
        <.button size="sm" variant="ghost" phx-click="reject_proposal" phx-value-card-id={@card.id}>
          Reject
        </.button>
      </div>
    </.card_wrapper>
    """
  end

  def lodge_card(%{card: %{type: "augury"}} = assigns) do
    ~H"""
    <div class="rounded-xl border-2 border-primary/20 bg-primary/5 p-6 space-y-3">
      <div class="flex items-start justify-between gap-4">
        <div>
          <span class="text-xs font-semibold uppercase tracking-widest text-primary/60">The Augury</span>
          <h2 class="text-lg font-semibold mt-0.5">{@card.title}</h2>
        </div>
        <div class="flex gap-2 shrink-0">
          <.button type="button" variant="outline" size="sm" phx-click="edit_augury" phx-value-card-id={@card.id}>
            Edit
          </.button>
          <.card_actions card={@card} />
        </div>
      </div>
      <.md_body body={@card.body} />
    </div>
    """
  end

  # Fallback
  def lodge_card(assigns) do
    ~H"""
    <.card_wrapper card={@card}>
      <.md_body body={@card.body} />
    </.card_wrapper>
    """
  end

  # Shared sub-components

  attr :card, :map, required: true
  slot :inner_block, required: true

  defp card_wrapper(assigns) do
    ~H"""
    <div class="rounded-lg border bg-card p-5 space-y-2">
      <.card_header card={@card} />
      {render_slot(@inner_block)}
      <.card_actions card={@card} />
    </div>
    """
  end

  defp card_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center gap-2 min-w-0">
        <span class="font-medium truncate">{@card.title}</span>
        <.badge variant="outline" class="text-xs shrink-0">{@card.type}</.badge>
        <%= if @card.pinned do %>
          <span class="text-xs text-muted-foreground shrink-0" title="pinned">📌</span>
        <% end %>
      </div>
    </div>
    """
  end

  defp card_actions(assigns) do
    ~H"""
    <div class="flex gap-1 justify-end">
      <.button type="button" variant="ghost" size="sm" phx-click="toggle_pin" phx-value-card-id={@card.id}>
        {if @card.pinned, do: "Unpin", else: "Pin"}
      </.button>
      <.button type="button" variant="ghost" size="sm" phx-click="dismiss_card" phx-value-card-id={@card.id}>
        Dismiss
      </.button>
      <.button type="button" variant="ghost" size="sm" phx-click="delete_card" phx-value-card-id={@card.id} data-confirm="Delete this card?">
        Delete
      </.button>
    </div>
    """
  end

  defp md_body(assigns) do
    ~H"""
    <%= if @body && @body != "" do %>
      <div class="prose prose-sm dark:prose-invert max-w-none">
        {Phoenix.HTML.raw(ExCortexWeb.Markdown.render(@body))}
      </div>
    <% end %>
    """
  end
end
```

**Step 4: Run tests**

Run: `mix test test/ex_cortex_web/components/lodge_cards_test.exs`
Expected: All 7 tests pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex_web/components/lodge_cards.ex test/ex_cortex_web/components/lodge_cards_test.exs
git commit -m "feat: add Lodge card renderer components for all card types"
```

---

## Task 5: Rebuild Lodge LiveView as Card Workspace

**Files:**
- Modify: `lib/ex_cortex_web/live/lodge_live.ex`
- Modify: `test/ex_cortex_web/live/lodge_live_test.exs`

**Step 1: Write the failing test**

Replace the existing lodge_live_test.exs content. The new Lodge shows cards instead of dashboard widgets.

Add to `test/ex_cortex_web/live/lodge_live_test.exs`:

```elixir
# Keep the existing setup and banner/redirect tests, then add:

describe "card workspace" do
  test "shows empty state when no cards exist", %{conn: conn} do
    insert_member()
    {:ok, _view, html} = live(conn, "/lodge")
    assert html =~ "Lodge"
    assert html =~ "No cards yet"
  end

  test "shows cards", %{conn: conn} do
    insert_member()
    ExCortex.Lodge.create_card(%{type: "note", title: "Hello World", body: "test", source: "manual"})
    {:ok, _view, html} = live(conn, "/lodge")
    assert html =~ "Hello World"
  end

  test "can create a note card", %{conn: conn} do
    insert_member()
    {:ok, view, _html} = live(conn, "/lodge")

    view
    |> form("form[phx-submit=create_card]", %{
      "card" => %{"type" => "note", "title" => "New Note", "body" => "content"}
    })
    |> render_submit()

    assert render(view) =~ "New Note"
  end

  test "can dismiss a card", %{conn: conn} do
    insert_member()
    {:ok, card} = ExCortex.Lodge.create_card(%{type: "note", title: "Dismiss Me", source: "manual"})
    {:ok, view, _html} = live(conn, "/lodge")
    assert render(view) =~ "Dismiss Me"

    render_click(view, "dismiss_card", %{"card-id" => to_string(card.id)})
    refute render(view) =~ "Dismiss Me"
  end

  test "can toggle pin", %{conn: conn} do
    insert_member()
    {:ok, card} = ExCortex.Lodge.create_card(%{type: "note", title: "Pin Me", source: "manual"})
    {:ok, view, _html} = live(conn, "/lodge")

    render_click(view, "toggle_pin", %{"card-id" => to_string(card.id)})
    html = render(view)
    assert html =~ "pinned" or html =~ "Unpin"
  end
end
```

**Step 2: Rewrite Lodge LiveView**

Replace the existing `lodge_live.ex` with the card workspace. Keep the banner redirect and member check logic. Remove dashboard widget rendering. Add card CRUD events.

In `/home/andrew/projects/ex_cortex/lib/ex_cortex_web/live/lodge_live.ex`:

Remove these imports (they'll move to Grimoire later):
```elixir
import ExCellenceDashboard.Components.AgentHealth
import ExCellenceDashboard.Components.CalibrationChart
import ExCellenceDashboard.Components.DriftMonitor
import ExCellenceDashboard.Components.OutcomeTracker
import ExCellenceDashboard.Components.ReplayViewer
```

Add:
```elixir
import ExCortexWeb.Components.LodgeCards
alias ExCortex.Lodge
```

Replace `load_dashboard_data/1` with:
```elixir
defp load_cards(socket) do
  cards = Lodge.list_cards()
  assign(socket, cards: cards)
end
```

Replace `handle_event` functions with card-oriented handlers:
```elixir
def handle_event("create_card", %{"card" => params}, socket) do
  attrs = Map.put(params, "source", "manual")
  case Lodge.create_card(attrs) do
    {:ok, _} -> {:noreply, load_cards(socket)}
    {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to create card")}
  end
end

def handle_event("dismiss_card", %{"card-id" => id}, socket) do
  card = Lodge.get_card!(id)
  Lodge.dismiss_card(card)
  {:noreply, load_cards(socket)}
end

def handle_event("delete_card", %{"card-id" => id}, socket) do
  card = Lodge.get_card!(id)
  Lodge.delete_card(card)
  {:noreply, load_cards(socket)}
end

def handle_event("toggle_pin", %{"card-id" => id}, socket) do
  card = Lodge.get_card!(id)
  Lodge.toggle_pin(card)
  {:noreply, load_cards(socket)}
end

def handle_event("toggle_checklist_item", %{"card-id" => id, "index" => idx}, socket) do
  card = Lodge.get_card!(id)
  Lodge.toggle_checklist_item(card, String.to_integer(idx))
  {:noreply, load_cards(socket)}
end

def handle_event("approve_proposal", %{"card-id" => id}, socket) do
  card = Lodge.get_card!(id)
  proposal_id = card.metadata["proposal_id"]
  if proposal_id do
    proposal = ExCortex.Repo.get(ExCortex.Quests.Proposal, proposal_id)
    if proposal, do: ExCortex.Quests.approve_proposal(proposal)
  end
  Lodge.dismiss_card(card)
  {:noreply, load_cards(socket)}
end

def handle_event("reject_proposal", %{"card-id" => id}, socket) do
  card = Lodge.get_card!(id)
  proposal_id = card.metadata["proposal_id"]
  if proposal_id do
    proposal = ExCortex.Repo.get(ExCortex.Quests.Proposal, proposal_id)
    if proposal, do: ExCortex.Quests.reject_proposal(proposal)
  end
  Lodge.dismiss_card(card)
  {:noreply, load_cards(socket)}
end
```

Replace the render template with:
```heex
<div class="space-y-6">
  <div>
    <h1 class="text-3xl font-bold tracking-tight">Lodge</h1>
    <p class="text-muted-foreground mt-1.5">
      Your guild's bulletin board — notes, checklists, alerts, and quest output.
    </p>
  </div>

  <%!-- Create card form --%>
  <div class="rounded-lg border border-dashed p-4">
    <form phx-submit="create_card" class="flex flex-col gap-3 sm:flex-row sm:items-end">
      <div class="flex-1 space-y-2">
        <div class="flex gap-2">
          <select name="card[type]" class="h-9 text-sm border border-input rounded-md px-3 bg-background">
            <option value="note">Note</option>
            <option value="checklist">Checklist</option>
            <option value="meeting">Meeting</option>
            <option value="alert">Alert</option>
            <option value="link">Link</option>
          </select>
          <input type="text" name="card[title]" placeholder="Title" required
            class="flex-1 h-9 text-sm border border-input rounded-md px-3 bg-background" />
        </div>
        <textarea name="card[body]" rows="2" placeholder="Body (markdown)"
          class="w-full text-sm border border-input rounded-md px-3 py-2 bg-background"></textarea>
      </div>
      <.button type="submit" size="sm">+ Add Card</.button>
    </form>
  </div>

  <%!-- Card feed --%>
  <%= if @cards == [] do %>
    <div class="rounded-lg border p-8 text-center">
      <p class="text-muted-foreground text-sm">
        No cards yet. Add one above or run a quest that posts to the Lodge.
      </p>
    </div>
  <% else %>
    <div class="space-y-4">
      <%= for card <- @cards do %>
        <.lodge_card card={card} />
      <% end %>
    </div>
  <% end %>
</div>
```

Update `mount_lodge/1` to call `load_cards/1` and subscribe to "lodge" PubSub:
```elixir
defp mount_lodge(socket) do
  import Ecto.Query

  has_members =
    ExCortex.Repo.exists?(from(r in Member, where: r.type == "role"))

  if has_members do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCortex.PubSub, "lodge")
    end

    {:ok, load_cards(assign(socket, page_title: "Lodge"))}
  else
    {:ok, push_navigate(socket, to: ~p"/town-square")}
  end
end
```

Update `handle_info` to reload cards:
```elixir
def handle_info({:lodge_card_posted, _card}, socket) do
  {:noreply, load_cards(socket)}
end

def handle_info(_msg, socket) do
  {:noreply, socket}
end
```

**Step 3: Run tests**

Run: `mix test test/ex_cortex_web/live/lodge_live_test.exs`
Expected: Pass. Some old tests about proposals/decisions may need removal since that content moved.

**Step 4: Commit**

```bash
git add lib/ex_cortex_web/live/lodge_live.ex test/ex_cortex_web/live/lodge_live_test.exs
git commit -m "feat: rebuild Lodge as card workspace with create/dismiss/pin/delete"
```

---

## Task 6: Migrate Proposals to Lodge Cards

**Files:**
- Modify: `lib/ex_cortex/lodge.ex`
- Modify: `lib/ex_cortex_web/live/lodge_live.ex`

**Step 1: Write the failing test**

Add to `test/ex_cortex/lodge_test.exs`:

```elixir
describe "sync_proposals/0" do
  test "creates cards for pending proposals that don't have cards yet" do
    {:ok, step} = ExCortex.Quests.create_step(%{name: "Sync Step", trigger: "manual", roster: []})
    {:ok, proposal} = ExCortex.Quests.create_proposal(%{
      quest_id: step.id,
      type: "roster_change",
      description: "Narrow roster",
      status: "pending"
    })

    Lodge.sync_proposals()
    cards = Lodge.list_cards(type: "proposal")
    assert length(cards) == 1
    assert hd(cards).metadata["proposal_id"] == proposal.id
  end

  test "does not duplicate cards for already-synced proposals" do
    {:ok, step} = ExCortex.Quests.create_step(%{name: "Sync Step 2", trigger: "manual", roster: []})
    {:ok, _} = ExCortex.Quests.create_proposal(%{
      quest_id: step.id,
      type: "other",
      description: "Already here",
      status: "pending"
    })

    Lodge.sync_proposals()
    Lodge.sync_proposals()
    cards = Lodge.list_cards(type: "proposal")
    assert length(cards) == 1
  end
end
```

**Step 2: Run test to verify it fails**

Expected: `sync_proposals/0` undefined.

**Step 3: Implement sync_proposals/0**

Add to `lib/ex_cortex/lodge.ex`:

```elixir
def sync_proposals do
  pending = ExCortex.Quests.list_proposals(status: "pending")
  existing_ids = list_cards(type: "proposal")
    |> Enum.map(& &1.metadata["proposal_id"])
    |> MapSet.new()

  for proposal <- pending, proposal.id not in existing_ids do
    create_card(%{
      type: "proposal",
      title: proposal.description,
      body: proposal.details["suggestion"] || "",
      source: "quest",
      quest_id: proposal.quest_id,
      metadata: %{
        "proposal_id" => proposal.id,
        "proposal_type" => proposal.type
      }
    })
  end
end
```

**Step 4: Call sync_proposals in Lodge mount**

In `lodge_live.ex`, call `Lodge.sync_proposals()` inside `mount_lodge/1` before `load_cards/1`.

**Step 5: Run tests**

Run: `mix test test/ex_cortex/lodge_test.exs test/ex_cortex_web/live/lodge_live_test.exs`
Expected: Pass.

**Step 6: Commit**

```bash
git add lib/ex_cortex/lodge.ex lib/ex_cortex_web/live/lodge_live.ex test/ex_cortex/lodge_test.exs
git commit -m "feat: sync pending proposals as Lodge cards"
```

---

## Task 7: Move Augury from Grimoire to Lodge

**Files:**
- Modify: `lib/ex_cortex/lodge.ex`
- Modify: `lib/ex_cortex_web/live/lodge_live.ex`
- Modify: `lib/ex_cortex_web/live/grimoire_live.ex`

**Step 1: Write the failing test**

Add to `test/ex_cortex/lodge_test.exs`:

```elixir
describe "sync_augury/0" do
  test "creates an augury card from the lore entry tagged augury" do
    ExCortex.Lore.create_entry(%{title: "World Read", body: "Markets shifting", tags: ["augury"], source: "manual"})
    Lodge.sync_augury()
    cards = Lodge.list_cards(type: "augury")
    assert length(cards) == 1
    assert hd(cards).title == "World Read"
    assert hd(cards).pinned == true
  end
end
```

**Step 2: Implement sync_augury/0**

Add to `lib/ex_cortex/lodge.ex`:

```elixir
def sync_augury do
  augury_entry =
    ExCortex.Lore.list_entries(tags: ["augury"], sort: "newest")
    |> List.first()

  existing = list_cards(type: "augury") |> List.first()

  cond do
    is_nil(augury_entry) -> :noop
    existing -> update_card(existing, %{title: augury_entry.title, body: augury_entry.body})
    true -> create_card(%{type: "augury", title: augury_entry.title, body: augury_entry.body, source: "manual", pinned: true})
  end
end
```

**Step 3: Call sync_augury in Lodge mount**

Add `Lodge.sync_augury()` call in `mount_lodge/1`.

**Step 4: Remove Augury section from Grimoire**

In `grimoire_live.ex`, remove the entire Augury hero section (the `<%= if @augury do %>...` block) and the augury loading from `reload/1`. Keep the lore entry feed and Drop In.

**Step 5: Run tests**

Run: `mix test test/ex_cortex/lodge_test.exs test/ex_cortex_web/live/grimoire_live_test.exs test/ex_cortex_web/live/lodge_live_test.exs`
Expected: Pass. May need to update grimoire tests that reference the augury.

**Step 6: Commit**

```bash
git add lib/ex_cortex/lodge.ex lib/ex_cortex_web/live/lodge_live.ex lib/ex_cortex_web/live/grimoire_live.ex test/
git commit -m "feat: move Augury from Grimoire to Lodge as pinned card"
```

---

## Task 8: Lodge Source Type

**Files:**
- Create: `lib/ex_cortex/sources/lodge_source.ex`
- Modify: `lib/ex_cortex/sources/source.ex` (add "lodge" to valid types)

**Step 1: Write the failing test**

Create `test/ex_cortex/sources/lodge_source_test.exs`:

```elixir
defmodule ExCortex.Sources.LodgeSourceTest do
  use ExCortex.DataCase

  alias ExCortex.Sources.LodgeSource

  describe "fetch/1" do
    test "returns active lodge cards as content items" do
      ExCortex.Lodge.create_card(%{type: "note", title: "Test Note", body: "content", source: "manual"})
      ExCortex.Lodge.create_card(%{type: "checklist", title: "TODO", body: "", source: "manual",
        metadata: %{"items" => [%{"text" => "Do thing", "checked" => false}]}})

      items = LodgeSource.fetch(%{"types" => ["note", "checklist"]})
      assert length(items) == 2
      assert Enum.any?(items, &(&1.title == "Test Note"))
    end

    test "filters by pinned only" do
      ExCortex.Lodge.create_card(%{type: "note", title: "Not pinned", body: "", source: "manual"})
      ExCortex.Lodge.create_card(%{type: "note", title: "Pinned", body: "", source: "manual", pinned: true})

      items = LodgeSource.fetch(%{"pinned_only" => true})
      assert length(items) == 1
      assert hd(items).title == "Pinned"
    end
  end
end
```

**Step 2: Implement LodgeSource**

Create `lib/ex_cortex/sources/lodge_source.ex`:

```elixir
defmodule ExCortex.Sources.LodgeSource do
  @moduledoc "Source adapter that reads active Lodge cards for quest consumption."

  import Ecto.Query

  alias ExCortex.Lodge.Card
  alias ExCortex.Repo

  def fetch(config \\ %{}) do
    query = from(c in Card, where: c.status == "active", order_by: [desc: c.pinned, desc: c.inserted_at])

    query =
      case config["types"] do
        nil -> query
        types when is_list(types) -> where(query, [c], c.type in ^types)
        _ -> query
      end

    query =
      if config["pinned_only"] do
        where(query, [c], c.pinned == true)
      else
        query
      end

    Repo.all(query)
    |> Enum.map(fn card ->
      %{
        title: card.title,
        body: card.body,
        type: card.type,
        metadata: card.metadata,
        source: "lodge"
      }
    end)
  end
end
```

**Step 3: Add "lodge" to Source valid types**

In `lib/ex_cortex/sources/source.ex`, find the `validate_inclusion(:source_type, ...)` call and add `"lodge"` to the list.

**Step 4: Run tests**

Run: `mix test test/ex_cortex/sources/lodge_source_test.exs`
Expected: Pass.

**Step 5: Commit**

```bash
git add lib/ex_cortex/sources/lodge_source.ex lib/ex_cortex/sources/source.ex test/ex_cortex/sources/lodge_source_test.exs
git commit -m "feat: add Lodge source type for quest consumption of cards"
```

---

## Task 9: Rebuild Grimoire as Quest Log — Overview Tab

**Files:**
- Modify: `lib/ex_cortex_web/live/grimoire_live.ex`
- Modify: `test/ex_cortex_web/live/grimoire_live_test.exs`

**Step 1: Write the failing test**

Add to `test/ex_cortex_web/live/grimoire_live_test.exs`:

```elixir
describe "quest log navigation" do
  test "shows overview tab by default with monitoring widgets", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/grimoire")
    assert html =~ "Overview"
    assert html =~ "Recent Decisions"
  end

  test "shows quest list in sidebar", %{conn: conn} do
    {:ok, step} = ExCortex.Quests.create_step(%{name: "Log Step", trigger: "manual", roster: []})
    {:ok, _} = ExCortex.Quests.create_quest(%{name: "Test Quest", trigger: "manual", steps: [%{"step_id" => step.id, "flow" => "always"}]})
    {:ok, _view, html} = live(conn, "/grimoire")
    assert html =~ "Test Quest"
  end
end
```

**Step 2: Implement overview tab**

In `grimoire_live.ex`:

Add the dashboard component imports that were removed from Lodge:
```elixir
import ExCellenceDashboard.Components.AgentHealth
import ExCellenceDashboard.Components.CalibrationChart
import ExCellenceDashboard.Components.DriftMonitor
import ExCellenceDashboard.Components.OutcomeTracker
import ExCellenceDashboard.Components.ReplayViewer
```

Add `alias ExCortex.TrustScorer`

Add to assigns in mount:
```elixir
grimoire_tab: "overview",
selected_quest_id: nil,
# Dashboard data (from old Lodge)
decisions: [],
outcomes: [],
outcome_stats: %{total: 0, resolved: 0, pending: 0, correct: 0, false_positives: 0, false_negatives: 0, success_rate: 0.0},
agents: [],
drift_result: {:ok, :insufficient_data},
calibration_buckets: [],
trust_scores: []
```

Add `load_dashboard_data/1` (moved from old Lodge — the function that queries decisions, outcomes, etc.).

Add tab-switching event:
```elixir
def handle_event("set_grimoire_tab", %{"tab" => tab}, socket) do
  socket = assign(socket, grimoire_tab: tab, selected_quest_id: nil)
  socket = if tab == "overview", do: load_dashboard_data(socket), else: socket
  {:noreply, socket}
end

def handle_event("select_quest", %{"id" => id}, socket) do
  quest_id = String.to_integer(id)
  {:noreply, assign(socket, grimoire_tab: "quest", selected_quest_id: quest_id) |> load_quest_data(quest_id)}
end
```

Update the render template to add tabs: Overview | Entries | Drop In, plus a quest sidebar.

**Step 3: Run tests**

Run: `mix test test/ex_cortex_web/live/grimoire_live_test.exs`
Expected: Pass.

**Step 4: Commit**

```bash
git add lib/ex_cortex_web/live/grimoire_live.ex test/ex_cortex_web/live/grimoire_live_test.exs
git commit -m "feat: add overview tab to Grimoire with relocated monitoring widgets"
```

---

## Task 10: Grimoire Per-Quest Drill-Down

**Files:**
- Modify: `lib/ex_cortex_web/live/grimoire_live.ex`

**Step 1: Write the failing test**

Add to `test/ex_cortex_web/live/grimoire_live_test.exs`:

```elixir
describe "per-quest view" do
  test "clicking a quest shows its runs and lore entries", %{conn: conn} do
    {:ok, step} = ExCortex.Quests.create_step(%{name: "Drill Step", trigger: "manual", roster: []})
    {:ok, quest} = ExCortex.Quests.create_quest(%{name: "Drill Quest", trigger: "manual", steps: [%{"step_id" => step.id, "flow" => "always"}]})
    ExCortex.Lore.create_entry(%{title: "From drill", body: "data", tags: [], quest_id: quest.id})

    {:ok, view, _html} = live(conn, "/grimoire")
    html = render_click(view, "select_quest", %{"id" => to_string(quest.id)})
    assert html =~ "Drill Quest"
    assert html =~ "From drill"
  end
end
```

**Step 2: Implement per-quest view**

Add `load_quest_data/2` to grimoire_live.ex:

```elixir
defp load_quest_data(socket, quest_id) do
  import Ecto.Query

  quest = ExCortex.Quests.get_quest!(quest_id)
  quest_runs = ExCortex.Quests.list_quest_runs(quest)
  lore_entries = ExCortex.Lore.list_entries(quest_id: quest_id)

  # Scoped decisions — filter by step_ids belonging to this quest
  step_ids = Enum.map(quest.steps || [], & &1["step_id"]) |> Enum.reject(&is_nil/1)

  assign(socket,
    selected_quest: quest,
    quest_runs: quest_runs,
    quest_lore_entries: lore_entries
  )
end
```

In the render template, when `@grimoire_tab == "quest"`, show:
- Quest name and description
- Run history table
- Lore entries generated by this quest
- Monitoring widgets scoped to this quest (future enhancement — for now just show runs + lore)

**Step 3: Run tests**

Run: `mix test test/ex_cortex_web/live/grimoire_live_test.exs`
Expected: Pass.

**Step 4: Commit**

```bash
git add lib/ex_cortex_web/live/grimoire_live.ex test/ex_cortex_web/live/grimoire_live_test.exs
git commit -m "feat: add per-quest drill-down view to Grimoire"
```

---

## Task 11: Full Test Suite Fix-up

**Step 1: Run full test suite**

Run: `mix test`

**Step 2: Fix any broken tests**

Common issues:
- Old Lodge tests asserting on dashboard widgets (decisions, outcomes) — remove or update
- Grimoire tests referencing augury (moved to Lodge) — remove augury assertions from grimoire tests
- Snapshot tests may need regeneration: `mix test --update-snapshots` or delete old snapshots

**Step 3: Format**

Run: `mix format`

**Step 4: Run full suite again**

Run: `mix test`
Expected: All green.

**Step 5: Commit**

```bash
git add -A
git commit -m "fix: update tests for Lodge/Grimoire redesign"
```

---

## Summary

| Task | What | Key Files |
|------|------|-----------|
| 1 | Absorb ex_cellence_ui → ExCortexUI | lib/ex_cortex_ui/ |
| 2 | Lodge cards schema + migration | lodge/card.ex, migration |
| 3 | Lodge context module | lodge.ex |
| 4 | Card renderer components | lodge_cards.ex |
| 5 | Rebuild Lodge LiveView | lodge_live.ex |
| 6 | Migrate proposals to cards | lodge.ex |
| 7 | Move Augury to Lodge | lodge.ex, grimoire_live.ex |
| 8 | Lodge source type | lodge_source.ex, source.ex |
| 9 | Grimoire overview tab | grimoire_live.ex |
| 10 | Per-quest drill-down | grimoire_live.ex |
| 11 | Full test suite fix-up | various |
