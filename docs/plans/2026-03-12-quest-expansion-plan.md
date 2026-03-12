# Quest Expansion & Lodge Dashboard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add 15 new quests, upgrade the lodge to a typed card dashboard with pinned zones, and wire dangerous tool calls through a proposal queue.

**Architecture:** Schema migrations add new columns to lodge_cards and proposals. Lodge context gains upsert-by-pin-slug and card versioning. Step runner intercepts dangerous tool calls. Lodge LiveView splits into pinned grid + chronological feed. Everyday Council charter gets 15 new quest definitions and updated campaigns.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto, PostgreSQL (jsonb), SaladUI components

---

## Task 0: Add Task.Supervisor for Obsidian Sync

**Files:**
- Modify: `lib/ex_calibur/application.ex:25` (add new supervisor)
- Modify: `lib/ex_calibur/lodge.ex:59` (replace Task.start)
- Modify: `lib/ex_calibur/lore.ex` (replace any Task.start)

**Step 1: Add TaskSupervisor to application supervision tree**

In `lib/ex_calibur/application.ex`, add after the existing `SourceTaskSupervisor`:

```elixir
{Task.Supervisor, name: ExCalibur.AsyncTaskSupervisor},
```

**Step 2: Replace Task.start in Lodge.post_card**

In `lib/ex_calibur/lodge.ex:59`, replace:

```elixir
Task.start(fn -> ExCalibur.Obsidian.Sync.sync_lodge_card(card) end)
```

with:

```elixir
Task.Supervisor.start_child(ExCalibur.AsyncTaskSupervisor, fn ->
  ExCalibur.Obsidian.Sync.sync_lodge_card(card)
end)
```

**Step 3: Replace any Task.start in Lore**

Search `lib/ex_calibur/lore.ex` for `Task.start` and replace the same way.

**Step 4: Run tests**

Run: `mix test test/ex_calibur_web/live/lodge_live_test.exs --trace`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/ex_calibur/application.ex lib/ex_calibur/lodge.ex lib/ex_calibur/lore.ex
git commit -m "refactor: use Task.Supervisor for fire-and-forget Obsidian sync"
```

---

## Task 1: Lodge Card Schema Migration

**Files:**
- Create: `priv/repo/migrations/20260312000001_upgrade_lodge_cards.exs`
- Modify: `lib/ex_calibur/lodge/card.ex`

**Step 1: Write the migration**

```elixir
defmodule ExCalibur.Repo.Migrations.UpgradeLodgeCards do
  use Ecto.Migration

  def change do
    alter table(:lodge_cards) do
      add :card_type, :string, default: "briefing"
      add :pin_slug, :string
      add :pin_order, :integer, default: 0
      add :guild_name, :string
    end

    create unique_index(:lodge_cards, [:pin_slug], where: "pin_slug IS NOT NULL")

    create table(:lodge_card_versions) do
      add :card_id, references(:lodge_cards, on_delete: :delete_all), null: false
      add :body, :text
      add :metadata, :map, default: %{}
      add :replaced_at, :utc_datetime, null: false
    end

    create index(:lodge_card_versions, [:card_id])
  end
end
```

**Step 2: Update Card schema**

In `lib/ex_calibur/lodge/card.ex`, update `@valid_types` to include the new types:

```elixir
@valid_types ~w(note checklist meeting alert link proposal augury briefing action_list table media metric freeform)
```

Add new fields to the schema block (after `status` field, line 19):

```elixir
field :card_type, :string, default: "briefing"
field :pin_slug, :string
field :pin_order, :integer, default: 0
field :guild_name, :string
```

Update the cast list in `changeset/2` to include the new fields:

```elixir
|> cast(attrs, [:type, :title, :body, :metadata, :pinned, :source, :quest_id, :status, :tags, :card_type, :pin_slug, :pin_order, :guild_name])
```

Add unique constraint after validate_inclusion:

```elixir
|> unique_constraint(:pin_slug)
```

**Step 3: Run migration**

Run: `mix ecto.migrate`
Expected: Migration succeeds

**Step 4: Run existing tests**

Run: `mix test test/ex_calibur_web/live/lodge_live_test.exs --trace`
Expected: All pass (no behavior change yet)

**Step 5: Commit**

```bash
git add priv/repo/migrations/20260312000001_upgrade_lodge_cards.exs lib/ex_calibur/lodge/card.ex
git commit -m "feat: add card_type, pin_slug, pin_order, guild_name to lodge_cards + versions table"
```

---

## Task 2: Proposal Schema Migration

**Files:**
- Create: `priv/repo/migrations/20260312000002_upgrade_proposals.exs`
- Modify: `lib/ex_calibur/quests/proposal.ex`

**Step 1: Write the migration**

```elixir
defmodule ExCalibur.Repo.Migrations.UpgradeProposals do
  use Ecto.Migration

  def change do
    alter table(:excellence_proposals) do
      add :tool_name, :string
      add :tool_args, :map, default: %{}
      add :context, :text
      add :result, :text
    end
  end
end
```

**Step 2: Update Proposal schema**

In `lib/ex_calibur/quests/proposal.ex`, add fields to schema (after `applied_at`):

```elixir
field :tool_name, :string
field :tool_args, :map, default: %{}
field :context, :string
field :result, :string
```

Update `@optional` to include the new fields:

```elixir
@optional [:quest_run_id, :details, :status, :applied_at, :tool_name, :tool_args, :context, :result]
```

Add `"executed"` and `"failed"` to valid statuses:

```elixir
|> validate_inclusion(:status, ["pending", "approved", "rejected", "applied", "executed", "failed"])
```

Add `"tool_action"` to valid types:

```elixir
|> validate_inclusion(:type, ["roster_change", "schedule_change", "prompt_change", "other", "tool_action"])
```

**Step 3: Run migration**

Run: `mix ecto.migrate`
Expected: Migration succeeds

**Step 4: Run tests**

Run: `mix test --trace`
Expected: All pass

**Step 5: Commit**

```bash
git add priv/repo/migrations/20260312000002_upgrade_proposals.exs lib/ex_calibur/quests/proposal.ex
git commit -m "feat: add tool_name, tool_args, context, result to proposals"
```

---

## Task 3: Lodge Card Version Schema

**Files:**
- Create: `lib/ex_calibur/lodge/card_version.ex`

**Step 1: Create CardVersion schema**

```elixir
defmodule ExCalibur.Lodge.CardVersion do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "lodge_card_versions" do
    field :body, :string
    field :metadata, :map, default: %{}
    field :replaced_at, :utc_datetime

    belongs_to :card, ExCalibur.Lodge.Card
  end

  def changeset(version, attrs) do
    version
    |> cast(attrs, [:card_id, :body, :metadata, :replaced_at])
    |> validate_required([:card_id, :replaced_at])
  end
end
```

**Step 2: Commit**

```bash
git add lib/ex_calibur/lodge/card_version.ex
git commit -m "feat: add CardVersion schema for pinned card history"
```

---

## Task 4: Lodge Context — Upsert by Pin Slug + Versioning

**Files:**
- Modify: `lib/ex_calibur/lodge.ex`
- Create: `test/ex_calibur/lodge_test.exs`

**Step 1: Write failing test for upsert_card**

Create `test/ex_calibur/lodge_test.exs`:

```elixir
defmodule ExCalibur.LodgeTest do
  use ExCalibur.DataCase

  alias ExCalibur.Lodge

  describe "upsert_card/1" do
    test "creates a new card when pin_slug does not exist" do
      assert {:ok, card} =
               Lodge.upsert_card(%{
                 type: "briefing",
                 card_type: "briefing",
                 title: "Test Card",
                 body: "Hello",
                 source: "quest",
                 pin_slug: "test-card",
                 pinned: true
               })

      assert card.pin_slug == "test-card"
      assert card.pinned == true
    end

    test "updates existing card when pin_slug matches, saving version" do
      {:ok, original} =
        Lodge.upsert_card(%{
          type: "briefing",
          card_type: "briefing",
          title: "V1",
          body: "Original body",
          source: "quest",
          pin_slug: "test-card",
          pinned: true
        })

      {:ok, updated} =
        Lodge.upsert_card(%{
          type: "briefing",
          card_type: "briefing",
          title: "V2",
          body: "Updated body",
          source: "quest",
          pin_slug: "test-card",
          pinned: true
        })

      assert updated.id == original.id
      assert updated.title == "V2"
      assert updated.body == "Updated body"

      versions = ExCalibur.Repo.all(ExCalibur.Lodge.CardVersion)
      assert length(versions) == 1
      assert hd(versions).body == "Original body"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_calibur/lodge_test.exs --trace`
Expected: FAIL — `upsert_card/1` not defined

**Step 3: Implement upsert_card and update list_cards**

In `lib/ex_calibur/lodge.ex`, add after `post_card/1`:

```elixir
def upsert_card(%{pin_slug: slug} = attrs) when is_binary(slug) and slug != "" do
  case Repo.one(from(c in Card, where: c.pin_slug == ^slug)) do
    nil ->
      create_card(attrs)

    existing ->
      # Save version before overwriting
      %ExCalibur.Lodge.CardVersion{}
      |> ExCalibur.Lodge.CardVersion.changeset(%{
        card_id: existing.id,
        body: existing.body,
        metadata: existing.metadata,
        replaced_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

      update_card(existing, attrs)
  end
end

def upsert_card(attrs), do: create_card(attrs)
```

Update `post_card/1` to use upsert when pin_slug is present:

```elixir
def post_card(%{pin_slug: slug} = attrs) when is_binary(slug) and slug != "" do
  case upsert_card(attrs) do
    {:ok, card} ->
      Phoenix.PubSub.broadcast(ExCalibur.PubSub, "lodge", {:lodge_card_posted, card})
      Task.Supervisor.start_child(ExCalibur.AsyncTaskSupervisor, fn ->
        ExCalibur.Obsidian.Sync.sync_lodge_card(card)
      end)
      {:ok, card}

    error ->
      error
  end
end
```

Update `list_cards/1` to sort pinned cards by `pin_order`:

```elixir
def list_cards(opts \\ []) do
  query =
    from(c in Card,
      where: c.status == "active",
      order_by: [desc: c.pinned, asc: c.pin_order, desc: c.inserted_at]
    )
  # ... rest unchanged
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ex_calibur/lodge_test.exs --trace`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_calibur/lodge.ex test/ex_calibur/lodge_test.exs
git commit -m "feat: add upsert_card with pin_slug matching and card versioning"
```

---

## Task 5: New Lodge Card Type Components

**Files:**
- Modify: `lib/ex_calibur_web/components/lodge_cards.ex`

This task adds 5 new card type renderers: `briefing`, `action_list`, `table`, `media`, `metric`, `freeform`. The existing `checklist` renderer already works. The existing `note` renderer covers simple markdown.

**Step 1: Add briefing renderer**

After the existing `lodge_card(%{card: %{type: "note"}})` clause (line 20), add:

```elixir
def lodge_card(%{card: %{type: "briefing"}} = assigns) do
  ~H"""
  <.lodge_card_frame card={@card}>
    <.md_body body={@card.body} />
  </.lodge_card_frame>
  """
end
```

**Step 2: Add action_list renderer**

```elixir
def lodge_card(%{card: %{type: "action_list"}} = assigns) do
  items = assigns.card.metadata["items"] || []
  action_labels = assigns.card.metadata["action_labels"] || %{}
  approve_label = action_labels["approve"] || "Approve"
  reject_label = action_labels["reject"] || "Reject"
  assigns = assign(assigns, items: items, approve_label: approve_label, reject_label: reject_label)

  ~H"""
  <.lodge_card_frame card={@card}>
    <div class="space-y-2">
      <%= for item <- @items do %>
        <div class={[
          "flex items-center justify-between gap-3 rounded-md border p-3 text-sm",
          item["status"] == "approved" && "bg-green-50 dark:bg-green-950/20",
          item["status"] == "rejected" && "bg-red-50 dark:bg-red-950/20 opacity-60"
        ]}>
          <div>
            <div class="font-medium">{item["label"]}</div>
            <%= if item["detail"] do %>
              <div class="text-xs text-muted-foreground">{item["detail"]}</div>
            <% end %>
          </div>
          <%= if item["status"] == "pending" do %>
            <div class="flex gap-1.5 shrink-0">
              <.button
                size="sm"
                variant="outline"
                phx-click="action_list_approve"
                phx-value-card-id={@card.id}
                phx-value-item-id={item["id"]}
              >
                {@approve_label}
              </.button>
              <.button
                size="sm"
                variant="ghost"
                phx-click="action_list_reject"
                phx-value-card-id={@card.id}
                phx-value-item-id={item["id"]}
              >
                {@reject_label}
              </.button>
            </div>
          <% else %>
            <.badge variant={if item["status"] == "approved", do: "default", else: "secondary"}>
              {item["status"]}
            </.badge>
          <% end %>
        </div>
      <% end %>
    </div>
  </.lodge_card_frame>
  """
end
```

**Step 3: Add table renderer**

```elixir
def lodge_card(%{card: %{type: "table"}} = assigns) do
  columns = assigns.card.metadata["columns"] || []
  rows = assigns.card.metadata["rows"] || []
  assigns = assign(assigns, columns: columns, rows: rows)

  ~H"""
  <.lodge_card_frame card={@card}>
    <.md_body body={@card.body} />
    <%= if @columns != [] do %>
      <div class="overflow-x-auto mt-2">
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b">
              <%= for col <- @columns do %>
                <th class="text-left py-1.5 px-2 font-medium text-muted-foreground">{col}</th>
              <% end %>
            </tr>
          </thead>
          <tbody>
            <%= for row <- @rows do %>
              <tr class="border-b last:border-0">
                <%= for col <- @columns do %>
                  <td class="py-1.5 px-2">{row[col] || ""}</td>
                <% end %>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    <% end %>
  </.lodge_card_frame>
  """
end
```

**Step 4: Add media renderer**

```elixir
def lodge_card(%{card: %{type: "media"}} = assigns) do
  thumbnail = assigns.card.metadata["thumbnail"] || assigns.card.metadata["url"]
  caption = assigns.card.metadata["caption"] || ""
  assigns = assign(assigns, thumbnail: thumbnail, caption: caption)

  ~H"""
  <.lodge_card_frame card={@card}>
    <%= if @thumbnail do %>
      <img src={@thumbnail} alt={@card.title} class="rounded-md max-h-64 object-cover w-full" />
    <% end %>
    <%= if @caption != "" do %>
      <p class="text-sm text-muted-foreground mt-1">{@caption}</p>
    <% end %>
    <.md_body body={@card.body} />
  </.lodge_card_frame>
  """
end
```

**Step 5: Add metric renderer**

```elixir
def lodge_card(%{card: %{type: "metric"}} = assigns) do
  value = assigns.card.metadata["value"] || "—"
  trend = assigns.card.metadata["trend"]
  trend_icon = case trend do
    "up" -> "↑"
    "down" -> "↓"
    "flat" -> "→"
    _ -> nil
  end
  trend_color = case trend do
    "up" -> "text-green-600 dark:text-green-400"
    "down" -> "text-red-600 dark:text-red-400"
    _ -> "text-muted-foreground"
  end
  assigns = assign(assigns, value: value, trend_icon: trend_icon, trend_color: trend_color)

  ~H"""
  <.lodge_card_frame card={@card}>
    <div class="flex items-baseline gap-2">
      <span class="text-3xl font-bold tracking-tight">{@value}</span>
      <%= if @trend_icon do %>
        <span class={"text-lg font-semibold " <> @trend_color}>{@trend_icon}</span>
      <% end %>
    </div>
    <.md_body body={@card.body} />
  </.lodge_card_frame>
  """
end
```

**Step 6: Add freeform renderer**

```elixir
def lodge_card(%{card: %{type: "freeform"}} = assigns) do
  ~H"""
  <.lodge_card_frame card={@card}>
    <.md_body body={@card.body} />
  </.lodge_card_frame>
  """
end
```

**Step 7: Update parse_artifact CARD_TYPE validation**

In `lib/ex_calibur/step_runner.ex:643`, update the valid card types:

```elixir
if ct in ~w(note checklist meeting alert link briefing action_list table media metric freeform), do: ct
```

Also update `@valid_card_types` at line 652:

```elixir
@valid_card_types ~w(note checklist meeting alert link briefing action_list table media metric freeform)
```

**Step 8: Run tests**

Run: `mix test --trace`
Expected: All pass

**Step 9: Commit**

```bash
git add lib/ex_calibur_web/components/lodge_cards.ex lib/ex_calibur/step_runner.ex
git commit -m "feat: add briefing, action_list, table, media, metric, freeform card renderers"
```

---

## Task 6: Lodge LiveView — Pinned Grid + Feed Layout

**Files:**
- Modify: `lib/ex_calibur_web/live/lodge_live.ex`

**Step 1: Update mount to separate pinned vs unpinned**

In `load_cards/1`, split cards into pinned and unpinned:

```elixir
defp load_cards(socket) do
  opts =
    case socket.assigns[:filter_tags] do
      [] -> []
      nil -> []
      tags -> [tags: tags]
    end

  cards = Lodge.list_cards(opts)
  pinned = Enum.filter(cards, & &1.pinned)
  feed = Enum.reject(cards, & &1.pinned)
  assign(socket, cards: cards, pinned_cards: pinned, feed_cards: feed)
end
```

**Step 2: Add action_list event handlers**

Add after the existing `toggle_checklist_item` handler:

```elixir
@impl true
def handle_event("action_list_approve", %{"card-id" => id, "item-id" => item_id}, socket) do
  update_action_list_item(id, item_id, "approved")
  {:noreply, load_cards(socket)}
end

@impl true
def handle_event("action_list_reject", %{"card-id" => id, "item-id" => item_id}, socket) do
  update_action_list_item(id, item_id, "rejected")
  {:noreply, load_cards(socket)}
end

defp update_action_list_item(card_id, item_id, status) do
  card = Lodge.get_card!(card_id)
  items = card.metadata["items"] || []

  updated_items =
    Enum.map(items, fn item ->
      if item["id"] == item_id, do: Map.put(item, "status", status), else: item
    end)

  Lodge.update_card(card, %{metadata: Map.put(card.metadata, "items", updated_items)})
end
```

**Step 3: Rewrite render to use pinned grid + feed**

Replace the card list section in `render/1` (lines 280-292) with:

```elixir
<%!-- Pinned Cards Grid --%>
<%= if @pinned_cards != [] do %>
  <div>
    <h2 class="text-sm font-medium text-muted-foreground mb-3">Pinned</h2>
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      <%= for card <- @pinned_cards do %>
        <div class={card_grid_class(card)}>
          <.lodge_card card={card} />
        </div>
      <% end %>
    </div>
  </div>
<% end %>

<%!-- Feed --%>
<div>
  <%= if @pinned_cards != [] do %>
    <h2 class="text-sm font-medium text-muted-foreground mb-3">Recent</h2>
  <% end %>
  <%= if @feed_cards == [] and @pinned_cards == [] do %>
    <div class="rounded-lg border p-8 text-center">
      <p class="text-muted-foreground text-sm">
        No cards yet. Add one above or run a quest that posts to the Lodge.
      </p>
    </div>
  <% else %>
    <div class="space-y-4">
      <%= for card <- @feed_cards do %>
        <.lodge_card card={card} />
      <% end %>
    </div>
  <% end %>
</div>
```

**Step 4: Add card_grid_class helper**

Add a private function to determine card width based on type:

```elixir
defp card_grid_class(%{type: "metric"}), do: "col-span-1"
defp card_grid_class(%{type: type}) when type in ~w(briefing table), do: "md:col-span-2 lg:col-span-2"
defp card_grid_class(%{type: "action_list"}), do: "col-span-1 md:col-span-2 lg:col-span-3"
defp card_grid_class(_), do: "col-span-1"
```

**Step 5: Update card creation form type selector**

Add new types to the `<select>` in the card creation form:

```html
<option value="briefing">Briefing</option>
<option value="note">Note</option>
<option value="checklist">Checklist</option>
<option value="table">Table</option>
<option value="metric">Metric</option>
<option value="freeform">Freeform</option>
<option value="meeting">Meeting</option>
<option value="alert">Alert</option>
<option value="link">Link</option>
```

**Step 6: Run tests**

Run: `mix test test/ex_calibur_web/live/lodge_live_test.exs --trace`
Expected: All pass

**Step 7: Commit**

```bash
git add lib/ex_calibur_web/live/lodge_live.ex
git commit -m "feat: lodge dashboard with pinned grid + feed layout and action_list handlers"
```

---

## Task 7: Step Runner — Dangerous Tool Interception

**Files:**
- Modify: `lib/ex_calibur/step_runner.ex`
- Create: `test/ex_calibur/step_runner_dangerous_test.exs`

**Step 1: Write failing test**

```elixir
defmodule ExCalibur.StepRunnerDangerousTest do
  use ExCalibur.DataCase

  alias ExCalibur.StepRunner

  describe "dangerous tool interception" do
    test "dangerous?/1 returns true for dangerous tools" do
      assert StepRunner.dangerous?("send_email")
      assert StepRunner.dangerous?("create_github_issue")
      refute StepRunner.dangerous?("web_search")
      refute StepRunner.dangerous?("query_lore")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ex_calibur/step_runner_dangerous_test.exs --trace`
Expected: FAIL — function not exported

**Step 3: Add dangerous tool interception**

In `lib/ex_calibur/step_runner.ex`, add the dangerous tool list and interception function near the top:

```elixir
@dangerous_tools ~w(send_email create_github_issue comment_github run_quest)

def dangerous?(tool_name), do: tool_name in @dangerous_tools
```

Add a function that creates a proposal instead of executing a dangerous tool:

```elixir
def intercept_dangerous_tool(tool_name, tool_args, quest_id, context \\ nil) do
  ExCalibur.Quests.create_proposal(%{
    quest_id: quest_id,
    type: "tool_action",
    description: "Tool call: #{tool_name}",
    details: %{"suggestion" => context || "Automated tool call"},
    status: "pending",
    tool_name: tool_name,
    tool_args: tool_args,
    context: context
  })
end
```

**Step 4: Run test**

Run: `mix test test/ex_calibur/step_runner_dangerous_test.exs --trace`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_calibur/step_runner.ex test/ex_calibur/step_runner_dangerous_test.exs
git commit -m "feat: add dangerous tool interception with proposal creation"
```

---

## Task 8: Step Runner — Multi-Card Output

**Files:**
- Modify: `lib/ex_calibur/step_runner.ex` (run/2 lodge_card clause)
- Modify: `lib/ex_calibur/quest_runner.ex` (result_to_text for lodge_card)

**Step 1: Update lodge_card run clause to support pin_slug and multi-card**

In `lib/ex_calibur/step_runner.ex`, replace the `run(%{output_type: "lodge_card"})` clause (lines 163-187):

```elixir
def run(%{output_type: "lodge_card"} = quest, input_text) do
  context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
  augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

  case run_artifact(quest, augmented) do
    {:ok, attrs} ->
      cards_spec = quest[:cards] || []

      if cards_spec != [] do
        # Multi-card mode: create one card per spec
        posted =
          Enum.map(cards_spec, fn spec ->
            card_attrs = %{
              type: spec["card_type"] || "briefing",
              card_type: spec["card_type"] || "briefing",
              title: attrs.title,
              body: attrs.body,
              tags: attrs[:tags] || [],
              source: "quest",
              quest_id: quest[:id],
              metadata: attrs[:metadata] || %{},
              pin_slug: spec["pin_slug"],
              pinned: spec["pinned"] || false,
              pin_order: spec["pin_order"] || 0,
              guild_name: quest[:guild_name]
            }

            ExCalibur.Lodge.post_card(card_attrs)
          end)

        {:ok, %{lodge_cards: posted}}
      else
        # Single card mode
        card_type = attrs[:card_type] || parse_card_type(quest.description) || "note"
        pin_slug = quest[:pin_slug]
        pinned = quest[:pinned] || false

        card_attrs = %{
          type: card_type,
          card_type: card_type,
          title: attrs.title,
          body: attrs.body,
          tags: attrs[:tags] || [],
          source: "quest",
          quest_id: quest[:id],
          metadata: attrs[:metadata] || %{},
          pin_slug: pin_slug,
          pinned: pinned,
          pin_order: quest[:pin_order] || 0,
          guild_name: quest[:guild_name]
        }

        ExCalibur.Lodge.post_card(card_attrs)
        {:ok, %{lodge_card: card_attrs}}
      end

    error ->
      error
  end
end
```

**Step 2: Add result_to_text clause for lodge_card in quest_runner**

In `lib/ex_calibur/quest_runner.ex`, add before the catch-all `result_to_text`:

```elixir
def result_to_text({:ok, %{lodge_card: %{title: title, body: body}}}, step_name, next_step_name) do
  question =
    if next_step_name,
      do: "\n**Open question for #{next_step_name}:** How does this card inform your evaluation?",
      else: ""

  """
  ## Prior Step: #{step_name}
  **Lodge Card:** #{title}
  #{String.slice(body || "", 0, 500)}#{question}
  """
end

def result_to_text({:ok, %{lodge_cards: _cards}}, step_name, _next) do
  "## Prior Step: #{step_name}\nMultiple lodge cards posted.\n"
end
```

**Step 3: Run tests**

Run: `mix test --trace`
Expected: All pass

**Step 4: Commit**

```bash
git add lib/ex_calibur/step_runner.ex lib/ex_calibur/quest_runner.ex
git commit -m "feat: support pin_slug, multi-card output, and guild_name in lodge_card quests"
```

---

## Task 9: Proposal Execution on Approve

**Files:**
- Modify: `lib/ex_calibur_web/live/lodge_live.ex` (approve_proposal handler)
- Modify: `lib/ex_calibur/quests.ex` (add execute_proposal)

**Step 1: Check existing approve_proposal logic**

Read `lib/ex_calibur/quests.ex` to find `approve_proposal/1`.

**Step 2: Add execute_proposal for tool_action proposals**

In the Quests context, add a function that executes the saved tool call when a tool_action proposal is approved:

```elixir
def execute_tool_proposal(%Proposal{type: "tool_action", tool_name: tool_name, tool_args: tool_args} = proposal) do
  case ExCalibur.Tools.Registry.get(tool_name) do
    nil ->
      update_proposal(proposal, %{status: "failed", result: "Tool #{tool_name} not found"})

    tool_mod ->
      case tool_mod.call(tool_args) do
        {:ok, result} ->
          update_proposal(proposal, %{status: "executed", result: to_string(result)})

        {:error, reason} ->
          update_proposal(proposal, %{status: "failed", result: inspect(reason)})
      end
  end
end
```

**Step 3: Update approve_proposal handler in LodgeLive**

In `lodge_live.ex`, update the `approve_proposal` handler to check for tool_action proposals and execute them:

```elixir
def handle_event("approve_proposal", %{"card-id" => id}, socket) do
  card = Lodge.get_card!(id)
  proposal_id = card.metadata["proposal_id"]

  if proposal_id do
    proposal = ExCalibur.Repo.get(Proposal, proposal_id)

    if proposal do
      ExCalibur.Quests.approve_proposal(proposal)

      if proposal.type == "tool_action" do
        ExCalibur.Quests.execute_tool_proposal(proposal)
      end
    end
  end

  Lodge.dismiss_card(card)
  {:noreply, load_cards(socket)}
end
```

**Step 4: Run tests**

Run: `mix test test/ex_calibur_web/live/lodge_live_test.exs --trace`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/ex_calibur/quests.ex lib/ex_calibur_web/live/lodge_live.ex
git commit -m "feat: execute tool_action proposals on approve"
```

---

## Task 10: Lodge Header with Guild Identity

**Files:**
- Modify: `lib/ex_calibur_web/components/lodge_cards.ex` (header)

**Step 1: Update lodge_card_header to show guild badge and type icon**

In `lodge_cards.ex`, update `lodge_card_header/1` to display guild_name badge and a type icon:

```elixir
defp lodge_card_header(assigns) do
  tags = Map.get(assigns.card, :tags, []) || []
  guild = Map.get(assigns.card, :guild_name, nil)
  type_icon = type_icon(assigns.card.type)
  assigns = assign(assigns, tags: tags, guild: guild, type_icon: type_icon)

  ~H"""
  <div class="flex items-center justify-between gap-2">
    <div class="flex items-center gap-2 min-w-0 flex-wrap">
      <%= if @type_icon do %>
        <span class="text-sm" title={@card.type}>{@type_icon}</span>
      <% end %>
      <span class="font-medium truncate">{@card.title}</span>
      <%= if @guild do %>
        <.badge variant="outline" class={"text-[10px] shrink-0 " <> guild_color(@guild)}>
          {@guild}
        </.badge>
      <% end %>
      <.badge variant="outline" class="text-xs shrink-0">{@card.type}</.badge>
      <%= if @card.pinned do %>
        <span class="text-xs text-muted-foreground shrink-0" title="pinned">pinned</span>
      <% end %>
      <%= for tag <- @tags do %>
        <.badge variant="outline" class={"text-[10px] shrink-0 " <> tag_color(tag)}>
          {tag}
        </.badge>
      <% end %>
    </div>
  </div>
  """
end

defp type_icon("briefing"), do: "📜"
defp type_icon("checklist"), do: "☑️"
defp type_icon("action_list"), do: "⚖️"
defp type_icon("table"), do: "📊"
defp type_icon("media"), do: "🖼️"
defp type_icon("metric"), do: "📈"
defp type_icon("freeform"), do: "✏️"
defp type_icon(_), do: nil

defp guild_color("tech"), do: "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300"
defp guild_color("lifestyle"), do: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300"
defp guild_color("business"), do: "bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300"
defp guild_color(_), do: ""
```

**Step 2: Run tests**

Run: `mix test --trace`
Expected: All pass

**Step 3: Commit**

```bash
git add lib/ex_calibur_web/components/lodge_cards.ex
git commit -m "feat: add type icons and guild badges to lodge card headers"
```

---

## Task 11: Everyday Council — New Quest Definitions

**Files:**
- Modify: `lib/ex_calibur/charters/everyday_council.ex`

**Step 1: Replace Journal Intake with Smart Intake**

In `quest_definitions/0`, replace the Journal Intake quest (lines 184-198):

```elixir
%{
  name: "Smart Intake",
  description:
    "Intelligent intake — drop a link, doc, image, video, email, or thought. Auto-detects content type and routes to appropriate tools for extraction, then summarizes, tags, and cross-references.",
  status: "active",
  trigger: "source",
  roster: [
    %{"who" => "apprentice", "preferred_who" => "journal-keeper", "when" => "on_trigger", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "artifact",
  write_mode: "append",
  entry_title_template: "Intake — {date}",
  loop_mode: "reflect",
  loop_tools: ["query_lore", "search_obsidian", "web_search", "web_fetch", "read_pdf", "describe_image", "read_image_text", "download_media", "extract_frames", "analyze_video", "create_obsidian_note"]
},
```

**Step 2: Add email quests after the News & Briefings section**

Add these quests before the Reflection section:

```elixir
# --- Email & GitHub ---
%{
  name: "Email Triage",
  description:
    "Morning email triage. Scan inbox, surface what matters, flag what needs action, dismiss the noise. Output as a pinned briefing card.",
  status: "active",
  trigger: "scheduled",
  schedule: "0 7 * * *",
  roster: [
    %{"who" => "journeyman", "preferred_who" => "news-correspondent", "when" => "on_trigger", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "lodge_card",
  pin_slug: "email-triage",
  pinned: true,
  pin_order: 1,
  loop_mode: "reflect",
  loop_tools: ["query_lore", "search_email", "read_email"]
},
%{
  name: "Email Cleanup",
  description:
    "Weekly email cleanup. Find subscriptions you never open, threads gone stale, and newsletters gathering dust. Present as an action list to unsubscribe or keep.",
  status: "active",
  trigger: "scheduled",
  schedule: "0 22 * * 0",
  roster: [
    %{"who" => "journeyman", "preferred_who" => "scope-realist", "when" => "on_trigger", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "lodge_card",
  pin_slug: "email-cleanup",
  pinned: true,
  loop_mode: "reflect",
  loop_tools: ["query_lore", "search_email", "read_email"]
},
%{
  name: "GitHub Pulse",
  description:
    "Daily GitHub activity check. Surface open PRs, new issues, notifications. Output as a pinned table card.",
  status: "active",
  trigger: "scheduled",
  schedule: "0 8 * * *",
  roster: [
    %{"who" => "apprentice", "preferred_who" => "evidence-collector", "when" => "on_trigger", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "lodge_card",
  pin_slug: "github-pulse",
  pinned: true,
  pin_order: 2,
  loop_mode: "reflect",
  loop_tools: ["query_lore", "search_github", "read_github_issue", "list_github_notifications"]
},
%{
  name: "GitHub Weekly",
  description:
    "Weekly GitHub summary. Merged PRs, closed issues, contribution patterns. Output as a briefing card.",
  status: "active",
  trigger: "scheduled",
  schedule: "0 9 * * 1",
  roster: [
    %{"who" => "journeyman", "preferred_who" => "the-historian", "when" => "on_trigger", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "lodge_card",
  loop_mode: "reflect",
  loop_tools: ["query_lore", "search_github", "read_github_issue"]
},
%{
  name: "Research Agent",
  description:
    "Deep research on a topic. Web search, cross-reference with lore and Obsidian, produce a comprehensive freeform artifact and lodge card.",
  status: "active",
  trigger: "manual",
  roster: [
    %{"who" => "apprentice", "preferred_who" => "evidence-collector", "when" => "on_trigger", "how" => "solo"},
    %{"who" => "journeyman", "preferred_who" => "challenger", "when" => "always", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "lodge_card",
  loop_mode: "reflect",
  loop_tools: ["query_lore", "web_search", "web_fetch", "search_obsidian", "read_obsidian", "search_email", "read_pdf"]
},
%{
  name: "Weekly Life Synthesis",
  description:
    "Sunday evening synthesis. Pull threads from journal, email, GitHub, and Obsidian into a holistic weekly briefing.",
  status: "active",
  trigger: "scheduled",
  schedule: "0 19 * * 0",
  roster: [
    %{"who" => "journeyman", "preferred_who" => "the-historian", "when" => "on_trigger", "how" => "solo"},
    %{"who" => "journeyman", "preferred_who" => "life-coach", "when" => "always", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "lodge_card",
  pin_slug: "weekly-synthesis",
  pinned: true,
  loop_mode: "reflect",
  loop_tools: ["query_lore", "search_obsidian", "read_obsidian", "search_email", "search_github"]
},

# --- Multi-Modal Intake ---
%{
  name: "PDF Deep Read",
  description:
    "Drop a PDF path. Extract, summarize, cross-reference with lore, optionally create an Obsidian note.",
  status: "active",
  trigger: "manual",
  roster: [
    %{"who" => "apprentice", "preferred_who" => "journal-keeper", "when" => "on_trigger", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "artifact",
  write_mode: "append",
  entry_title_template: "PDF Read — {date}",
  loop_mode: "reflect",
  loop_tools: ["read_pdf", "query_lore", "web_search", "create_obsidian_note"]
},
%{
  name: "Image Analysis",
  description:
    "Drop an image path. Describe, extract text, cross-reference with lore.",
  status: "active",
  trigger: "manual",
  roster: [
    %{"who" => "apprentice", "preferred_who" => "journal-keeper", "when" => "on_trigger", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "artifact",
  write_mode: "append",
  entry_title_template: "Image Analysis — {date}",
  loop_mode: "reflect",
  loop_tools: ["describe_image", "read_image_text", "query_lore"]
},
%{
  name: "Video Breakdown",
  description:
    "Drop a video URL or path. Download, extract key frames (max 20), analyze, create an Obsidian note with summary.",
  status: "active",
  trigger: "manual",
  roster: [
    %{"who" => "apprentice", "preferred_who" => "journal-keeper", "when" => "on_trigger", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "artifact",
  write_mode: "append",
  entry_title_template: "Video Breakdown — {date}",
  loop_mode: "reflect",
  loop_tools: ["download_media", "extract_frames", "analyze_video", "extract_audio", "create_obsidian_note", "query_lore"]
},

# --- Cross-Guild Intelligence ---
%{
  name: "Morning Command Brief",
  description:
    "7am comprehensive briefing. Pulls email highlights, GitHub activity, and today's priorities into a multi-card dashboard update.",
  status: "active",
  trigger: "scheduled",
  schedule: "0 7 * * *",
  roster: [
    %{"who" => "journeyman", "preferred_who" => "life-coach", "when" => "on_trigger", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "lodge_card",
  pin_slug: "command-brief",
  pinned: true,
  pin_order: 0,
  loop_mode: "reflect",
  loop_tools: ["query_lore", "search_email", "search_github", "list_github_notifications", "web_search", "search_obsidian"]
},
%{
  name: "Trend Detector",
  description:
    "Daily pattern detection. What topics keep recurring in your lore, searches, and notes? Surface as a metric card.",
  status: "active",
  trigger: "scheduled",
  schedule: "0 10 * * *",
  roster: [
    %{"who" => "journeyman", "preferred_who" => "the-historian", "when" => "on_trigger", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "lodge_card",
  pin_slug: "trend-detector",
  pinned: true,
  loop_mode: "reflect",
  loop_tools: ["query_lore", "web_search", "search_obsidian"]
},
%{
  name: "Obsidian Librarian",
  description:
    "Nightly vault maintenance. Find orphaned notes, broken links, missing tags. Present as a checklist card.",
  status: "active",
  trigger: "scheduled",
  schedule: "0 3 * * *",
  roster: [
    %{"who" => "apprentice", "preferred_who" => "journal-keeper", "when" => "on_trigger", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "lodge_card",
  pin_slug: "obsidian-librarian",
  pinned: true,
  loop_mode: "reflect",
  loop_tools: ["search_obsidian", "search_obsidian_content", "read_obsidian", "read_obsidian_frontmatter", "create_obsidian_note", "daily_obsidian"]
},

# --- Proactive Automation ---
%{
  name: "Issue Drafter",
  description:
    "Draft a GitHub issue based on research. Searches existing issues, cross-references lore, then queues the create_github_issue call for approval.",
  status: "active",
  trigger: "manual",
  roster: [
    %{"who" => "apprentice", "preferred_who" => "evidence-collector", "when" => "on_trigger", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "lodge_card",
  loop_mode: "reflect",
  loop_tools: ["search_github", "read_github_issue", "query_lore", "create_github_issue"]
},
%{
  name: "Email Responder",
  description:
    "Draft and queue an email response. Reads the thread, searches lore for context, drafts reply, queues send_email for approval.",
  status: "active",
  trigger: "manual",
  roster: [
    %{"who" => "journeyman", "preferred_who" => "news-correspondent", "when" => "on_trigger", "how" => "solo"}
  ],
  source_ids: [],
  output_type: "lodge_card",
  loop_mode: "reflect",
  loop_tools: ["read_email", "search_email", "query_lore", "web_search", "send_email"]
},
```

**Step 3: Run format**

Run: `mix format`

**Step 4: Commit**

```bash
git add lib/ex_calibur/charters/everyday_council.ex
git commit -m "feat: add 15 new quest definitions to Everyday Council (email, GitHub, research, multi-modal, automation)"
```

---

## Task 12: Everyday Council — Updated Campaign Definitions

**Files:**
- Modify: `lib/ex_calibur/charters/everyday_council.ex` (campaign_definitions)

**Step 1: Update campaign_definitions to match design**

Replace the entire `campaign_definitions/0` function:

```elixir
def campaign_definitions do
  [
    %{
      name: "Intake Loop",
      description: "Continuous source intake — anything you drop gets processed and logged automatically.",
      status: "active",
      trigger: "source",
      steps: [
        %{"quest_name" => "Smart Intake", "flow" => "always"}
      ],
      source_ids: []
    },
    %{
      name: "Morning Start",
      description: "Daily 7-8am — email triage, command brief, then check in.",
      status: "active",
      trigger: "scheduled",
      schedule: "0 7 * * *",
      steps: [
        %{"quest_name" => "Email Triage", "flow" => "always"},
        %{"quest_name" => "Morning Command Brief", "flow" => "always"},
        %{"quest_name" => "Daily Check-in", "flow" => "always"}
      ],
      source_ids: []
    },
    %{
      name: "Midday Check",
      description: "Noon — GitHub pulse then midday scope check.",
      status: "active",
      trigger: "scheduled",
      schedule: "0 12 * * *",
      steps: [
        %{"quest_name" => "GitHub Pulse", "flow" => "always"},
        %{"quest_name" => "Midday Pulse", "flow" => "always"}
      ],
      source_ids: []
    },
    %{
      name: "Evening Close",
      description: "Daily 9pm — wrap the day, log it, set up tomorrow.",
      status: "active",
      trigger: "scheduled",
      schedule: "0 21 * * *",
      steps: [
        %{"quest_name" => "Evening Wrap", "flow" => "always"}
      ],
      source_ids: []
    },
    %{
      name: "Weekly Close",
      description: "Friday evening — news digest, GitHub weekly, life synthesis, then reflection.",
      status: "active",
      trigger: "scheduled",
      schedule: "0 19 * * 5",
      steps: [
        %{"quest_name" => "Weekly News Digest", "flow" => "always"},
        %{"quest_name" => "GitHub Weekly", "flow" => "always"},
        %{"quest_name" => "Weekly Life Synthesis", "flow" => "always"},
        %{"quest_name" => "Weekly Reflection", "flow" => "always"}
      ],
      source_ids: []
    },
    %{
      name: "Monthly Close",
      description: "First of the month — deep review of everything logged.",
      status: "active",
      trigger: "scheduled",
      schedule: "0 10 1 * *",
      steps: [
        %{"quest_name" => "Monthly Review", "flow" => "always"}
      ],
      source_ids: []
    },
    %{
      name: "Nightly Maintenance",
      description: "3am — Obsidian vault cleanup, then trend detection.",
      status: "active",
      trigger: "scheduled",
      schedule: "0 3 * * *",
      steps: [
        %{"quest_name" => "Obsidian Librarian", "flow" => "always"},
        %{"quest_name" => "Trend Detector", "flow" => "always"}
      ],
      source_ids: []
    },
    %{
      name: "Weekly Cleanup",
      description: "Sunday night — email subscription cleanup.",
      status: "active",
      trigger: "scheduled",
      schedule: "0 22 * * 0",
      steps: [
        %{"quest_name" => "Email Cleanup", "flow" => "always"}
      ],
      source_ids: []
    }
  ]
end
```

**Step 2: Run format + tests**

Run: `mix format && mix test --trace`
Expected: All pass

**Step 3: Commit**

```bash
git add lib/ex_calibur/charters/everyday_council.ex
git commit -m "feat: update Everyday Council campaigns (morning start, midday, nightly, weekly cleanup)"
```

---

## Task 13: Step Schema — Pin/Card Fields

**Files:**
- Create: `priv/repo/migrations/20260312000003_add_card_fields_to_steps.exs`
- Modify: `lib/ex_calibur/quests/step.ex`

The step schema needs pin_slug, pinned, pin_order, guild_name, and cards fields so quests can declare card output behavior.

**Step 1: Write migration**

```elixir
defmodule ExCalibur.Repo.Migrations.AddCardFieldsToSteps do
  use Ecto.Migration

  def change do
    alter table(:excellence_steps) do
      add :pin_slug, :string
      add :pin_order, :integer, default: 0
      add :cards, :map, default: %{}
      add :guild_name, :string
    end
  end
end
```

**Step 2: Update Step schema**

Add to the Step schema fields (check existing fields first):

```elixir
field :pin_slug, :string
field :pin_order, :integer, default: 0
field :cards, :map, default: %{}
field :guild_name, :string
```

Add these to the cast list in the changeset.

**Step 3: Run migration + tests**

Run: `mix ecto.migrate && mix test --trace`
Expected: All pass

**Step 4: Commit**

```bash
git add priv/repo/migrations/20260312000003_add_card_fields_to_steps.exs lib/ex_calibur/quests/step.ex
git commit -m "feat: add pin_slug, pin_order, cards, guild_name to steps schema"
```

---

## Task 14: Lodge Live Tests — Pinned Grid + Action List

**Files:**
- Modify: `test/ex_calibur_web/live/lodge_live_test.exs`

**Step 1: Add tests for pinned grid rendering**

```elixir
test "renders pinned cards in grid section", %{conn: conn} do
  # Create a pinned card
  Lodge.create_card(%{
    type: "briefing",
    title: "Pinned Brief",
    body: "Important",
    source: "quest",
    pinned: true,
    pin_slug: "test-pin"
  })

  {:ok, view, _html} = live(conn, ~p"/lodge")
  assert has_element?(view, "h2", "Pinned")
  assert has_element?(view, "span", "Pinned Brief")
end

test "renders action_list card with approve/reject buttons", %{conn: conn} do
  Lodge.create_card(%{
    type: "action_list",
    title: "Cleanup",
    body: "",
    source: "quest",
    metadata: %{
      "items" => [
        %{"id" => "1", "label" => "Old Newsletter", "status" => "pending"},
        %{"id" => "2", "label" => "Security Alerts", "status" => "pending"}
      ],
      "action_labels" => %{"approve" => "Unsubscribe", "reject" => "Keep"}
    }
  })

  {:ok, view, _html} = live(conn, ~p"/lodge")
  assert has_element?(view, "button", "Unsubscribe")
  assert has_element?(view, "button", "Keep")
end
```

**Step 2: Run tests**

Run: `mix test test/ex_calibur_web/live/lodge_live_test.exs --trace`
Expected: All pass

**Step 3: Commit**

```bash
git add test/ex_calibur_web/live/lodge_live_test.exs
git commit -m "test: add lodge live tests for pinned grid and action_list cards"
```

---

## Notes

### Tool Count for Small Models
The per-member `loop_tools` lists keep tool counts manageable (3-12 tools per quest). Members with `"all_safe"` tools get the full 21, which may overwhelm small Ollama models. Consider adding a `max_tools` setting per member rank that truncates the tool list for apprentice-tier models.

### Frame Limits for Video
The `analyze_video` tool should limit extracted frames to a configurable max (default 20). This prevents a 2-hour video from spawning thousands of vision API calls. Add a `max_frames` parameter to the tool.

### CLI Health Checks
Consider adding a startup health check in application.ex that runs `System.find_executable/1` for key CLI tools (obsidian-cli, notmuch, msmtp, yt-dlp, ffmpeg) and logs warnings for missing binaries. Non-blocking — just advisory.
