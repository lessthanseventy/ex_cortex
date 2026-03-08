# Quests & Campaigns Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the quest + campaign system — named, saved evaluation pipelines that can be triggered manually, by sources, or on a schedule — replacing the stub QuestsLive and absorbing EvaluateLive.

**Architecture:** Quests and Campaigns are persisted in the server's DB (new Ecto schemas). Charters gain `quest_definitions/0` and `campaign_definitions/0` so guilds pre-install their quests on install. The `/quests` board replaces both `/quests` and `/evaluate`. Quest execution for v1 delegates to the existing `Evaluator` (full multi-roster execution with escalation is phase 2).

**Tech Stack:** Phoenix LiveView, Ecto (SQLite via ex_calibur Repo), ExCalibur.Evaluator for execution.

---

## Task 1: DB Migration — quests, campaigns, runs

**Files:**
- Create: `priv/repo/migrations/20260308220000_add_quests_and_campaigns.exs`

**Step 1: Write the migration**

```elixir
defmodule ExCalibur.Repo.Migrations.AddQuestsAndCampaigns do
  use Ecto.Migration

  def change do
    create table(:excellence_quests) do
      add :name, :string, null: false
      add :description, :string
      add :status, :string, null: false, default: "active"
      add :trigger, :string, null: false, default: "manual"
      add :schedule, :string
      add :roster, {:array, :map}, default: []
      add :source_ids, {:array, :string}, default: []
      timestamps()
    end

    create unique_index(:excellence_quests, [:name])

    create table(:excellence_quest_runs) do
      add :quest_id, references(:excellence_quests, on_delete: :delete_all)
      add :campaign_run_id, :integer
      add :input, :text
      add :status, :string, null: false, default: "pending"
      add :results, :map, default: %{}
      timestamps()
    end

    create index(:excellence_quest_runs, [:quest_id])
    create index(:excellence_quest_runs, [:campaign_run_id])

    create table(:excellence_campaigns) do
      add :name, :string, null: false
      add :description, :string
      add :status, :string, null: false, default: "active"
      add :trigger, :string, null: false, default: "manual"
      add :schedule, :string
      add :steps, {:array, :map}, default: []
      add :source_ids, {:array, :string}, default: []
      timestamps()
    end

    create unique_index(:excellence_campaigns, [:name])

    create table(:excellence_campaign_runs) do
      add :campaign_id, references(:excellence_campaigns, on_delete: :delete_all)
      add :status, :string, null: false, default: "pending"
      add :step_results, :map, default: %{}
      timestamps()
    end

    create index(:excellence_campaign_runs, [:campaign_id])
  end
end
```

**Step 2: Run it**

```bash
cd /home/andrew/projects/ex_calibur && mix ecto.migrate
```

Expected: `== Migrated 20260308220000 in 0.0s`

**Step 3: Commit**

```bash
git add priv/repo/migrations/20260308220000_add_quests_and_campaigns.exs
git commit -m "chore: add quests and campaigns migration"
```

---

## Task 2: Quest Schema

**Files:**
- Create: `lib/ex_calibur/quests/quest.ex`
- Create: `test/ex_calibur/quests/quest_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_calibur/quests/quest_test.exs
defmodule ExCalibur.Quests.QuestTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Quests.Quest

  test "changeset valid with required fields" do
    params = %{name: "WCAG Scan", trigger: "manual", roster: []}
    assert %{valid?: true} = Quest.changeset(%Quest{}, params)
  end

  test "changeset invalid without name" do
    assert %{valid?: false} = Quest.changeset(%Quest{}, %{trigger: "manual"})
  end

  test "changeset invalid without trigger" do
    assert %{valid?: false} = Quest.changeset(%Quest{}, %{name: "WCAG Scan"})
  end
end
```

**Step 2: Run to confirm failure**

```bash
mix test test/ex_calibur/quests/quest_test.exs
```

Expected: error — module not found.

**Step 3: Implement the schema**

```elixir
# lib/ex_calibur/quests/quest.ex
defmodule ExCalibur.Quests.Quest do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "excellence_quests" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "active"
    field :trigger, :string, default: "manual"
    field :schedule, :string
    field :roster, {:array, :map}, default: []
    field :source_ids, {:array, :string}, default: []
    timestamps()
  end

  @required [:name, :trigger]
  @optional [:description, :status, :schedule, :roster, :source_ids]

  def changeset(quest, attrs) do
    quest
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["active", "paused"])
    |> validate_inclusion(:trigger, ["manual", "source", "scheduled"])
    |> unique_constraint(:name)
  end
end
```

**Step 4: Run tests**

```bash
mix test test/ex_calibur/quests/quest_test.exs
```

Expected: 3 passing.

**Step 5: Commit**

```bash
git add lib/ex_calibur/quests/quest.ex test/ex_calibur/quests/quest_test.exs
git commit -m "feat: add Quest schema"
```

---

## Task 3: QuestRun, Campaign, CampaignRun Schemas

**Files:**
- Create: `lib/ex_calibur/quests/quest_run.ex`
- Create: `lib/ex_calibur/quests/campaign.ex`
- Create: `lib/ex_calibur/quests/campaign_run.ex`

**Step 1: Write them all**

```elixir
# lib/ex_calibur/quests/quest_run.ex
defmodule ExCalibur.Quests.QuestRun do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "excellence_quest_runs" do
    field :quest_id, :integer
    field :campaign_run_id, :integer
    field :input, :string
    field :status, :string, default: "pending"
    field :results, :map, default: %{}
    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:quest_id, :campaign_run_id, :input, :status, :results])
    |> validate_required([:quest_id, :input])
    |> validate_inclusion(:status, ["pending", "running", "complete", "failed"])
  end
end
```

```elixir
# lib/ex_calibur/quests/campaign.ex
defmodule ExCalibur.Quests.Campaign do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "excellence_campaigns" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "active"
    field :trigger, :string, default: "manual"
    field :schedule, :string
    field :steps, {:array, :map}, default: []
    field :source_ids, {:array, :string}, default: []
    timestamps()
  end

  @required [:name, :trigger]
  @optional [:description, :status, :schedule, :steps, :source_ids]

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["active", "paused"])
    |> validate_inclusion(:trigger, ["manual", "source", "scheduled"])
    |> unique_constraint(:name)
  end
end
```

```elixir
# lib/ex_calibur/quests/campaign_run.ex
defmodule ExCalibur.Quests.CampaignRun do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "excellence_campaign_runs" do
    field :campaign_id, :integer
    field :status, :string, default: "pending"
    field :step_results, :map, default: %{}
    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:campaign_id, :status, :step_results])
    |> validate_required([:campaign_id])
    |> validate_inclusion(:status, ["pending", "running", "complete", "failed"])
  end
end
```

**Step 2: Compile check**

```bash
mix compile --warnings-as-errors
```

Expected: clean compile.

**Step 3: Commit**

```bash
git add lib/ex_calibur/quests/
git commit -m "feat: add QuestRun, Campaign, CampaignRun schemas"
```

---

## Task 4: Quests Context Module

**Files:**
- Create: `lib/ex_calibur/quests.ex`
- Create: `test/ex_calibur/quests_test.exs`

**Step 1: Write failing tests**

```elixir
# test/ex_calibur/quests_test.exs
defmodule ExCalibur.QuestsTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Quests
  alias ExCalibur.Quests.Quest
  alias ExCalibur.Quests.Campaign

  describe "quests" do
    test "list_quests returns all quests" do
      {:ok, _} = Quests.create_quest(%{name: "Test Quest", trigger: "manual"})
      assert [%Quest{}] = Quests.list_quests()
    end

    test "create_quest with valid params" do
      assert {:ok, %Quest{name: "My Quest"}} =
               Quests.create_quest(%{name: "My Quest", trigger: "manual"})
    end

    test "create_quest with invalid params" do
      assert {:error, %Ecto.Changeset{}} = Quests.create_quest(%{})
    end

    test "update_quest changes fields" do
      {:ok, quest} = Quests.create_quest(%{name: "Quest A", trigger: "manual"})
      assert {:ok, %Quest{status: "paused"}} = Quests.update_quest(quest, %{status: "paused"})
    end

    test "delete_quest removes it" do
      {:ok, quest} = Quests.create_quest(%{name: "Quest B", trigger: "manual"})
      assert {:ok, _} = Quests.delete_quest(quest)
      assert Quests.list_quests() == []
    end
  end

  describe "campaigns" do
    test "list_campaigns returns all campaigns" do
      {:ok, _} = Quests.create_campaign(%{name: "Campaign A", trigger: "manual"})
      assert [%Campaign{}] = Quests.list_campaigns()
    end

    test "create_campaign with valid params" do
      assert {:ok, %Campaign{name: "My Campaign"}} =
               Quests.create_campaign(%{name: "My Campaign", trigger: "manual"})
    end
  end
end
```

**Step 2: Run to confirm failure**

```bash
mix test test/ex_calibur/quests_test.exs
```

Expected: error — module not found.

**Step 3: Implement context**

```elixir
# lib/ex_calibur/quests.ex
defmodule ExCalibur.Quests do
  @moduledoc false
  import Ecto.Query

  alias ExCalibur.Repo
  alias ExCalibur.Quests.Campaign
  alias ExCalibur.Quests.CampaignRun
  alias ExCalibur.Quests.Quest
  alias ExCalibur.Quests.QuestRun

  # --- Quests ---

  def list_quests do
    Repo.all(from q in Quest, order_by: [asc: q.name])
  end

  def get_quest!(id), do: Repo.get!(Quest, id)

  def create_quest(attrs) do
    %Quest{} |> Quest.changeset(attrs) |> Repo.insert()
  end

  def update_quest(%Quest{} = quest, attrs) do
    quest |> Quest.changeset(attrs) |> Repo.update()
  end

  def delete_quest(%Quest{} = quest), do: Repo.delete(quest)

  # --- Campaigns ---

  def list_campaigns do
    Repo.all(from c in Campaign, order_by: [asc: c.name])
  end

  def get_campaign!(id), do: Repo.get!(Campaign, id)

  def create_campaign(attrs) do
    %Campaign{} |> Campaign.changeset(attrs) |> Repo.insert()
  end

  def update_campaign(%Campaign{} = campaign, attrs) do
    campaign |> Campaign.changeset(attrs) |> Repo.update()
  end

  def delete_campaign(%Campaign{} = campaign), do: Repo.delete(campaign)

  # --- Quest Runs ---

  def list_quest_runs(%Quest{id: quest_id}) do
    Repo.all(
      from r in QuestRun,
        where: r.quest_id == ^quest_id,
        order_by: [desc: r.inserted_at],
        limit: 10
    )
  end

  def create_quest_run(attrs) do
    %QuestRun{} |> QuestRun.changeset(attrs) |> Repo.insert()
  end

  def update_quest_run(%QuestRun{} = run, attrs) do
    run |> QuestRun.changeset(attrs) |> Repo.update()
  end

  # --- Campaign Runs ---

  def list_campaign_runs(%Campaign{id: campaign_id}) do
    Repo.all(
      from r in CampaignRun,
        where: r.campaign_id == ^campaign_id,
        order_by: [desc: r.inserted_at],
        limit: 10
    )
  end

  def create_campaign_run(attrs) do
    %CampaignRun{} |> CampaignRun.changeset(attrs) |> Repo.insert()
  end

  def update_campaign_run(%CampaignRun{} = run, attrs) do
    run |> CampaignRun.changeset(attrs) |> Repo.update()
  end
end
```

**Step 4: Run tests**

```bash
mix test test/ex_calibur/quests_test.exs
```

Expected: all passing.

**Step 5: Commit**

```bash
git add lib/ex_calibur/quests.ex test/ex_calibur/quests_test.exs
git commit -m "feat: add Quests context"
```

---

## Task 5: Add quest_definitions/campaign_definitions to Charters

**Files:**
- Modify: `/home/andrew/projects/ex_cellence/lib/excellence/charters/accessibility_review.ex`
- Modify: all other charter files in the same directory (code_review, content_moderation, contract_review, dependency_audit, incident_triage, performance_audit, risk_assessment)
- Modify: `lib/ex_calibur_web/live/guild_hall_live.ex`

**Step 1: Add to AccessibilityReview charter**

Open `/home/andrew/projects/ex_cellence/lib/excellence/charters/accessibility_review.ex` and add after `resource_definitions/0`:

```elixir
def quest_definitions do
  [
    %{
      name: "WCAG Hourly Scan",
      description: "Quick automated accessibility check by apprentice members",
      status: "active",
      trigger: "scheduled",
      schedule: "@hourly",
      roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
      source_ids: []
    },
    %{
      name: "Full Accessibility Audit",
      description: "Comprehensive review by all members reaching consensus",
      status: "active",
      trigger: "manual",
      schedule: nil,
      roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
      source_ids: []
    }
  ]
end

def campaign_definitions do
  [
    %{
      name: "Monthly Accessibility Review",
      description: "Automated scan that escalates to full audit on any findings",
      status: "active",
      trigger: "scheduled",
      schedule: "@monthly",
      steps: [
        %{"quest_name" => "WCAG Hourly Scan", "flow" => "always"},
        %{"quest_name" => "Full Accessibility Audit", "flow" => "on_flag"}
      ],
      source_ids: []
    }
  ]
end
```

**Step 2: Add to each remaining charter**

For each of the 7 remaining charters, add sensible `quest_definitions/0` and `campaign_definitions/0`. Keep them simple — one "Quick Scan" quest (apprentice, scheduled hourly, solo) and one "Full Review" quest (all members, manual, consensus), and one campaign chaining them. The names should reflect the guild domain (e.g., "Code Quality Scan", "Full Code Review", "Daily Code Review Campaign").

**Step 3: Update guild_hall_live.ex — install quests and campaigns**

In `lib/ex_calibur_web/live/guild_hall_live.ex`, add aliases at top:

```elixir
alias ExCalibur.Quests
```

Update `confirm_install` event handler to also clear old quests/campaigns:

```elixir
import Ecto.Query

ExCalibur.Repo.delete_all(from(r in Member))
ExCalibur.Repo.delete_all(from(q in ExCalibur.Quests.Quest))
ExCalibur.Repo.delete_all(from(c in ExCalibur.Quests.Campaign))
```

Add `install_quests/1` and `install_campaigns/2` private functions after `install_guild/1`:

```elixir
defp install_quests(mod) do
  if function_exported?(mod, :quest_definitions, 0) do
    Enum.each(mod.quest_definitions(), fn attrs ->
      Quests.create_quest(attrs)
    end)
  end
end

defp install_campaigns(mod) do
  if function_exported?(mod, :campaign_definitions, 0) do
    quest_by_name =
      Quests.list_quests() |> Map.new(&{&1.name, &1.id})

    Enum.each(mod.campaign_definitions(), fn attrs ->
      steps =
        Enum.map(attrs.steps, fn step ->
          %{"quest_id" => Map.get(quest_by_name, step["quest_name"]), "flow" => step["flow"]}
        end)

      Quests.create_campaign(Map.put(attrs, :steps, steps))
    end)
  end
end
```

Call them in the `confirm_install` handler after `install_guild(mod)`:

```elixir
install_guild(mod)
install_quests(mod)
install_campaigns(mod)
create_default_sources(guild_name)
```

**Step 4: Compile check**

```bash
mix compile --warnings-as-errors
```

**Step 5: Commit**

```bash
git add /home/andrew/projects/ex_cellence/lib/excellence/charters/
git add lib/ex_calibur_web/live/guild_hall_live.ex
git commit -m "feat: add quest/campaign definitions to charters and guild install"
```

---

## Task 6: Rewrite QuestsLive

**Files:**
- Modify: `lib/ex_calibur_web/live/quests_live.ex`
- Create: `test/ex_calibur_web/live/quests_live_test.exs`

**Step 1: Write failing tests**

```elixir
# test/ex_calibur_web/live/quests_live_test.exs
defmodule ExCaliburWeb.QuestsLiveTest do
  use ExCaliburWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias ExCalibur.Quests

  setup do
    {:ok, quest} = Quests.create_quest(%{name: "Test Quest", trigger: "manual", roster: []})
    {:ok, campaign} = Quests.create_campaign(%{
      name: "Test Campaign",
      trigger: "manual",
      steps: [%{"quest_id" => quest.id, "flow" => "always"}]
    })
    %{quest: quest, campaign: campaign}
  end

  test "renders quest board with quests and campaigns", %{conn: conn, quest: quest, campaign: campaign} do
    {:ok, _view, html} = live(conn, "/quests")
    assert html =~ "Test Quest"
    assert html =~ "Test Campaign"
  end

  test "shows + New Quest button", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/quests")
    assert html =~ "New Quest"
  end

  test "shows + New Campaign button", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/quests")
    assert html =~ "New Campaign"
  end

  test "create_quest event adds a quest", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/quests")

    html =
      view
      |> form("form[phx-submit=\"create_quest\"]", %{
        "quest" => %{"name" => "New Quest", "trigger" => "manual", "who" => "all", "how" => "consensus"}
      })
      |> render_submit()

    assert html =~ "New Quest"
  end

  test "toggle_quest_status toggles active/paused", %{conn: conn, quest: quest} do
    {:ok, view, _html} = live(conn, "/quests")
    html = render_click(view, "toggle_quest_status", %{"id" => to_string(quest.id)})
    assert html =~ "paused" or html =~ "active"
  end

  test "delete_quest removes quest", %{conn: conn, quest: quest} do
    {:ok, view, _html} = live(conn, "/quests")
    html = render_click(view, "delete_quest", %{"id" => to_string(quest.id)})
    refute html =~ "Test Quest"
  end
end
```

**Step 2: Run to confirm failure**

```bash
mix test test/ex_calibur_web/live/quests_live_test.exs
```

Expected: failures — QuestsLive doesn't render the right things yet.

**Step 3: Rewrite QuestsLive**

```elixir
# lib/ex_calibur_web/live/quests_live.ex
defmodule ExCaliburWeb.QuestsLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge

  alias ExCalibur.Evaluator
  alias ExCalibur.Quests
  alias ExCalibur.Quests.Quest

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       quests: Quests.list_quests(),
       campaigns: Quests.list_campaigns(),
       expanded: MapSet.new(),
       adding_quest: false,
       adding_campaign: false,
       running: %{}
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Quests")}
  end

  @impl true
  def handle_event("toggle_expand", %{"id" => id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded, id),
        do: MapSet.delete(socket.assigns.expanded, id),
        else: MapSet.put(socket.assigns.expanded, id)

    {:noreply, assign(socket, expanded: expanded)}
  end

  @impl true
  def handle_event("add_quest", _, socket) do
    {:noreply, assign(socket, adding_quest: true, adding_campaign: false)}
  end

  @impl true
  def handle_event("add_campaign", _, socket) do
    {:noreply, assign(socket, adding_campaign: true, adding_quest: false)}
  end

  @impl true
  def handle_event("cancel_new", _, socket) do
    {:noreply, assign(socket, adding_quest: false, adding_campaign: false)}
  end

  @impl true
  def handle_event("create_quest", %{"quest" => params}, socket) do
    roster = [
      %{
        "who" => params["who"] || "all",
        "when" => "on_trigger",
        "how" => params["how"] || "consensus"
      }
    ]

    attrs = %{
      name: params["name"],
      description: params["description"],
      trigger: params["trigger"] || "manual",
      schedule: params["schedule"],
      roster: roster,
      status: "active"
    }

    case Quests.create_quest(attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(quests: Quests.list_quests(), adding_quest: false)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create quest")}
    end
  end

  @impl true
  def handle_event("create_campaign", %{"campaign" => params}, socket) do
    quest_ids =
      params
      |> Map.get("quest_ids", "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    steps =
      Enum.map(quest_ids, &%{"quest_id" => &1, "flow" => "always"})

    attrs = %{
      name: params["name"],
      description: params["description"],
      trigger: params["trigger"] || "manual",
      steps: steps,
      status: "active"
    }

    case Quests.create_campaign(attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(campaigns: Quests.list_campaigns(), adding_campaign: false)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create campaign")}
    end
  end

  @impl true
  def handle_event("toggle_quest_status", %{"id" => id}, socket) do
    quest = Quests.get_quest!(String.to_integer(id))
    new_status = if quest.status == "active", do: "paused", else: "active"
    Quests.update_quest(quest, %{status: new_status})
    {:noreply, assign(socket, quests: Quests.list_quests())}
  end

  @impl true
  def handle_event("toggle_campaign_status", %{"id" => id}, socket) do
    campaign = Quests.get_campaign!(String.to_integer(id))
    new_status = if campaign.status == "active", do: "paused", else: "active"
    Quests.update_campaign(campaign, %{status: new_status})
    {:noreply, assign(socket, campaigns: Quests.list_campaigns())}
  end

  @impl true
  def handle_event("delete_quest", %{"id" => id}, socket) do
    quest = Quests.get_quest!(String.to_integer(id))
    Quests.delete_quest(quest)
    {:noreply, assign(socket, quests: Quests.list_quests())}
  end

  @impl true
  def handle_event("delete_campaign", %{"id" => id}, socket) do
    campaign = Quests.get_campaign!(String.to_integer(id))
    Quests.delete_campaign(campaign)
    {:noreply, assign(socket, campaigns: Quests.list_campaigns())}
  end

  @impl true
  def handle_event("run_quest", %{"id" => id, "input" => input}, socket) when input != "" do
    quest = Quests.get_quest!(String.to_integer(id))
    run_id = to_string(quest.id)

    {:ok, quest_run} =
      Quests.create_quest_run(%{quest_id: quest.id, input: input, status: "running"})

    running = Map.put(socket.assigns.running, run_id, %{status: "running", result: nil})

    Task.start(fn ->
      result = Evaluator.evaluate(input)
      send(self(), {:quest_run_complete, run_id, quest_run.id, result})
    end)

    {:noreply, assign(socket, running: running)}
  end

  def handle_event("run_quest", _, socket) do
    {:noreply, put_flash(socket, :error, "Please enter some input to evaluate")}
  end

  @impl true
  def handle_info({:quest_run_complete, run_id, quest_run_id, result}, socket) do
    {status, results} =
      case result do
        {:ok, outcome} -> {"complete", outcome}
        {:error, reason} -> {"failed", %{error: inspect(reason)}}
      end

    quest_run = ExCalibur.Repo.get!(ExCalibur.Quests.QuestRun, quest_run_id)
    Quests.update_quest_run(quest_run, %{status: status, results: results})

    running = Map.put(socket.assigns.running, run_id, %{status: status, result: results})
    {:noreply, assign(socket, running: running)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Quests</h1>
        <div class="flex gap-2">
          <.button variant="outline" size="sm" phx-click="add_campaign">+ New Campaign</.button>
          <.button variant="outline" size="sm" phx-click="add_quest">+ New Quest</.button>
        </div>
      </div>

      <%= if @adding_quest do %>
        <.new_quest_form />
      <% end %>

      <%= if @adding_campaign do %>
        <.new_campaign_form quests={@quests} />
      <% end %>

      <%= if @campaigns != [] do %>
        <div>
          <h2 class="text-sm font-semibold text-muted-foreground uppercase tracking-wide mb-2">Campaigns</h2>
          <div class="space-y-2">
            <.campaign_card
              :for={campaign <- @campaigns}
              campaign={campaign}
              quests={@quests}
              expanded={MapSet.member?(@expanded, "campaign-#{campaign.id}")}
            />
          </div>
        </div>
      <% end %>

      <div>
        <h2 class="text-sm font-semibold text-muted-foreground uppercase tracking-wide mb-2">Quests</h2>
        <div class="space-y-2">
          <.quest_card
            :for={quest <- @quests}
            quest={quest}
            expanded={MapSet.member?(@expanded, "quest-#{quest.id}")}
            run_state={Map.get(@running, to_string(quest.id))}
          />
        </div>
      </div>
    </div>
    """
  end

  defp new_quest_form(assigns) do
    ~H"""
    <div class="border rounded-lg border-dashed p-4">
      <form phx-submit="create_quest" class="space-y-3">
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="text-sm font-medium">Name</label>
            <.input type="text" name="quest[name]" value="" placeholder="e.g. WCAG Hourly Scan" />
          </div>
          <div>
            <label class="text-sm font-medium">Description</label>
            <.input type="text" name="quest[description]" value="" placeholder="Optional" />
          </div>
        </div>
        <div class="grid grid-cols-3 gap-3">
          <div>
            <label class="text-sm font-medium">Who runs it</label>
            <select name="quest[who]" class="w-full text-sm border rounded px-2 py-1 bg-background">
              <option value="all">Everyone</option>
              <option value="apprentice">Apprentice tier</option>
              <option value="journeyman">Journeyman tier</option>
              <option value="master">Master tier</option>
            </select>
          </div>
          <div>
            <label class="text-sm font-medium">How</label>
            <select name="quest[how]" class="w-full text-sm border rounded px-2 py-1 bg-background">
              <option value="consensus">Consensus</option>
              <option value="solo">Solo</option>
              <option value="unanimous">Unanimous</option>
              <option value="first_to_pass">First to pass</option>
            </select>
          </div>
          <div>
            <label class="text-sm font-medium">Trigger</label>
            <select name="quest[trigger]" class="w-full text-sm border rounded px-2 py-1 bg-background">
              <option value="manual">Manual</option>
              <option value="source">Source</option>
              <option value="scheduled">Scheduled</option>
            </select>
          </div>
        </div>
        <div class="flex justify-end gap-2">
          <.button type="button" variant="outline" size="sm" phx-click="cancel_new">Cancel</.button>
          <.button type="submit" size="sm">Create Quest</.button>
        </div>
      </form>
    </div>
    """
  end

  attr :quests, :list, required: true

  defp new_campaign_form(assigns) do
    ~H"""
    <div class="border rounded-lg border-dashed p-4">
      <form phx-submit="create_campaign" class="space-y-3">
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="text-sm font-medium">Name</label>
            <.input type="text" name="campaign[name]" value="" placeholder="e.g. Monthly Audit" />
          </div>
          <div>
            <label class="text-sm font-medium">Description</label>
            <.input type="text" name="campaign[description]" value="" placeholder="Optional" />
          </div>
        </div>
        <div>
          <label class="text-sm font-medium">Quests (select in order)</label>
          <select name="campaign[quest_ids]" multiple class="w-full text-sm border rounded px-2 py-1 bg-background h-24">
            <%= for quest <- @quests do %>
              <option value={quest.id}>{quest.name}</option>
            <% end %>
          </select>
          <p class="text-xs text-muted-foreground mt-1">Hold Ctrl/Cmd to select multiple</p>
        </div>
        <div class="flex justify-end gap-2">
          <.button type="button" variant="outline" size="sm" phx-click="cancel_new">Cancel</.button>
          <.button type="submit" size="sm">Create Campaign</.button>
        </div>
      </form>
    </div>
    """
  end

  attr :campaign, :map, required: true
  attr :quests, :list, required: true
  attr :expanded, :boolean, required: true

  defp campaign_card(assigns) do
    ~H"""
    <div class={["border rounded-lg bg-card", if(@campaign.status == "paused", do: "opacity-60")]}>
      <div class="flex items-center gap-3 px-4 py-3">
        <div
          class="flex flex-1 items-center gap-3 cursor-pointer min-w-0"
          phx-click="toggle_expand"
          phx-value-id={"campaign-#{@campaign.id}"}
        >
          <span class={["transition-transform text-muted-foreground", if(@expanded, do: "rotate-90")]}>›</span>
          <div class="flex-1 min-w-0">
            <span class="font-medium">{@campaign.name}</span>
            <span class="text-xs text-muted-foreground ml-2">{length(@campaign.steps)} quests</span>
          </div>
          <.badge variant="outline" class="text-xs shrink-0">{@campaign.trigger}</.badge>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <.button
            size="sm"
            variant="ghost"
            phx-click="toggle_campaign_status"
            phx-value-id={@campaign.id}
          >
            {if @campaign.status == "active", do: "Pause", else: "Resume"}
          </.button>
          <.button
            size="sm"
            variant="ghost"
            phx-click="delete_campaign"
            phx-value-id={@campaign.id}
            data-confirm="Delete this campaign?"
          >
            Delete
          </.button>
        </div>
      </div>
      <%= if @expanded do %>
        <div class="border-t px-4 py-3 space-y-2">
          <%= if @campaign.description do %>
            <p class="text-sm text-muted-foreground">{@campaign.description}</p>
          <% end %>
          <div class="space-y-1">
            <%= for {step, idx} <- Enum.with_index(@campaign.steps) do %>
              <div class="flex items-center gap-2 text-sm">
                <span class="text-muted-foreground">{idx + 1}.</span>
                <span>{quest_name_for_step(step, @quests)}</span>
                <%= if idx < length(@campaign.steps) - 1 do %>
                  <.badge variant="secondary" class="text-xs">{step["flow"]}</.badge>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :quest, :map, required: true
  attr :expanded, :boolean, required: true
  attr :run_state, :map, default: nil

  defp quest_card(assigns) do
    ~H"""
    <div class={["border rounded-lg bg-card", if(@quest.status == "paused", do: "opacity-60")]}>
      <div class="flex items-center gap-3 px-4 py-3">
        <div
          class="flex flex-1 items-center gap-3 cursor-pointer min-w-0"
          phx-click="toggle_expand"
          phx-value-id={"quest-#{@quest.id}"}
        >
          <span class={["transition-transform text-muted-foreground", if(@expanded, do: "rotate-90")]}>›</span>
          <div class="flex-1 min-w-0">
            <span class="font-medium">{@quest.name}</span>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <.badge variant="outline" class="text-xs">{@quest.trigger}</.badge>
            <%= if roster_summary(@quest) != "" do %>
              <.badge variant="secondary" class="text-xs">{roster_summary(@quest)}</.badge>
            <% end %>
          </div>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <.button
            size="sm"
            variant="ghost"
            phx-click="toggle_quest_status"
            phx-value-id={@quest.id}
          >
            {if @quest.status == "active", do: "Pause", else: "Resume"}
          </.button>
          <.button
            size="sm"
            variant="ghost"
            phx-click="delete_quest"
            phx-value-id={@quest.id}
            data-confirm="Delete this quest?"
          >
            Delete
          </.button>
        </div>
      </div>
      <%= if @expanded do %>
        <div class="border-t px-4 py-4 space-y-3">
          <%= if @quest.description do %>
            <p class="text-sm text-muted-foreground">{@quest.description}</p>
          <% end %>
          <form phx-submit="run_quest" class="flex gap-2">
            <input type="hidden" name="id" value={@quest.id} />
            <.input
              type="textarea"
              name="input"
              value=""
              rows={3}
              placeholder="Paste content to evaluate..."
              class="flex-1 text-sm"
            />
            <div class="flex flex-col justify-end">
              <.button type="submit" size="sm">Run Now</.button>
            </div>
          </form>
          <%= if @run_state do %>
            <div class={["rounded p-3 text-sm", run_state_class(@run_state.status)]}>
              <span class="font-medium">{String.capitalize(@run_state.status)}</span>
              <%= if @run_state.result do %>
                <pre class="mt-1 text-xs overflow-auto">{inspect(@run_state.result, pretty: true)}</pre>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp roster_summary(%Quest{roster: []}), do: ""
  defp roster_summary(%Quest{roster: [first | _]}), do: "#{first["who"]} · #{first["how"]}"

  defp run_state_class("running"), do: "bg-blue-50 text-blue-700 border border-blue-200"
  defp run_state_class("complete"), do: "bg-green-50 text-green-700 border border-green-200"
  defp run_state_class("failed"), do: "bg-red-50 text-red-700 border border-red-200"
  defp run_state_class(_), do: "bg-muted text-muted-foreground"

  defp quest_name_for_step(step, quests) do
    quest = Enum.find(quests, &(to_string(&1.id) == to_string(step["quest_id"])))
    if quest, do: quest.name, else: "Unknown Quest"
  end
end
```

**Step 4: Run tests**

```bash
mix test test/ex_calibur_web/live/quests_live_test.exs
```

Expected: all passing.

**Step 5: Commit**

```bash
git add lib/ex_calibur_web/live/quests_live.ex test/ex_calibur_web/live/quests_live_test.exs
git commit -m "feat: rewrite QuestsLive as quest board with campaigns"
```

---

## Task 7: Remove /evaluate, update router and nav

**Files:**
- Modify: `lib/ex_calibur_web/router.ex`
- Modify: `lib/ex_calibur_web/components/layouts/root.html.heex`
- Delete (empty out): `lib/ex_calibur_web/live/evaluate_live.ex`

**Step 1: Update router** — remove evaluate routes, add redirect

```elixir
# In router.ex, replace:
live "/quests", QuestsLive, :index
live "/quests/new", QuestsLive, :new
live "/evaluate", EvaluateLive, :index

# With:
live "/quests", QuestsLive, :index
get "/evaluate", PageController, :redirect_evaluate
```

Actually, simpler — just redirect at the LiveView level. Replace the evaluate route with:

```elixir
live "/quests", QuestsLive, :index
```

And remove:
```elixir
live "/quests/new", QuestsLive, :new
live "/evaluate", EvaluateLive, :index
```

**Step 2: Update evaluate_live.ex to a simple redirect**

Replace the content of `lib/ex_calibur_web/live/evaluate_live.ex` with:

```elixir
defmodule ExCaliburWeb.EvaluateLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: "/quests")}
  end

  @impl true
  def render(assigns), do: ~H""
end
```

Keep the route for now so existing links don't 404, but redirect immediately.

**Step 3: Remove Evaluate from nav**

In `lib/ex_calibur_web/components/layouts/root.html.heex`, find and remove the Evaluate nav link.

**Step 4: Compile and smoke test**

```bash
mix compile --warnings-as-errors
```

**Step 5: Commit**

```bash
git add lib/ex_calibur_web/router.ex lib/ex_calibur_web/live/evaluate_live.ex lib/ex_calibur_web/components/layouts/root.html.heex
git commit -m "feat: remove /evaluate, redirect to /quests"
```

---

## Task 8: Add "Build your own guild" to GuildHallLive

**Files:**
- Modify: `lib/ex_calibur_web/live/guild_hall_live.ex`

**Step 1: Add event handler**

Add to `handle_event`:

```elixir
@impl true
def handle_event("build_own_guild", _, socket) do
  import Ecto.Query

  ExCalibur.Repo.delete_all(from(r in Member))
  ExCalibur.Repo.delete_all(from(q in ExCalibur.Quests.Quest))
  ExCalibur.Repo.delete_all(from(c in ExCalibur.Quests.Campaign))

  {:noreply,
   socket
   |> assign(current_guild: nil, confirming: nil)
   |> put_flash(:info, "Blank guild ready. Add members and quests to get started.")
   |> push_navigate(to: "/members")}
end
```

**Step 2: Add card to render**

At the bottom of the guilds list in `render/1`, add:

```elixir
<div class="flex items-center justify-between rounded-lg border border-dashed p-4 mt-4">
  <div class="space-y-1">
    <span class="font-semibold">Build Your Own Guild</span>
    <p class="text-sm text-muted-foreground">
      Start from scratch — add your own members and quests.
    </p>
  </div>
  <.button variant="outline" size="sm" phx-click="build_own_guild">
    Start Fresh
  </.button>
</div>
```

**Step 3: Compile check**

```bash
mix compile --warnings-as-errors
```

**Step 4: Run full test suite**

```bash
mix test
```

Expected: all passing (warnings as errors).

**Step 5: Commit**

```bash
git add lib/ex_calibur_web/live/guild_hall_live.ex
git commit -m "feat: add Build Your Own Guild option to guild hall"
```

---

## Task 9: Final wiring — run all tests, format, commit

**Step 1: Format**

```bash
mix format
```

**Step 2: Full test run**

```bash
mix test
```

Expected: all passing.

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: quests and campaigns system — board, CRUD, run now, guild pre-install"
```
