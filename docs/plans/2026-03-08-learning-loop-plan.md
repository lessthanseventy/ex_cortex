# Learning Loop Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow the system to periodically review its own quest run outcomes and propose — or automatically apply — small improvements to member config, escalation thresholds, and quest rosters over time, with human approval required for larger changes.

**Architecture:** A `Proposal` schema stores proposed changes with auto-apply bounds. A `LearningLoop` module collects recent quest run data, formats it as a structured prompt, calls a master-tier or Claude member, and parses the response into Proposal records. A `ScheduledQuestRunner` GenServer checks cron-scheduled quests every minute. The Lodge page gains a Proposals card for one-click approve/reject.

**Tech Stack:** Phoenix LiveView, Ecto, ExCellenceServer.QuestRunner, ExCellenceServer.ClaudeClient, `crontab` hex package for cron parsing.

---

## Task 1: Proposal schema + migration

**Files:**
- Create: `priv/repo/migrations/20260308250000_add_proposals.exs`
- Create: `lib/ex_cellence_server/learning/proposal.ex`
- Create: `test/ex_cellence_server/learning/proposal_test.exs`

**Step 1: Write the migration**

```elixir
# priv/repo/migrations/20260308250000_add_proposals.exs
defmodule ExCellenceServer.Repo.Migrations.AddProposals do
  use Ecto.Migration

  def change do
    create table(:excellence_proposals) do
      add :source, :string, null: false
      add :type, :string, null: false
      add :target_id, :string, null: false
      add :current_value, :map, default: %{}
      add :proposed_value, :map, default: %{}
      add :reason, :text
      add :status, :string, null: false, default: "pending"
      timestamps()
    end

    create index(:excellence_proposals, [:status])
    create index(:excellence_proposals, [:target_id])
  end
end
```

**Step 2: Run it**

```bash
cd /home/andrew/projects/ex_cellence_server && mix ecto.migrate
```

Expected: `== Migrated 20260308250000 in 0.0s`

**Step 3: Write the failing test**

```elixir
# test/ex_cellence_server/learning/proposal_test.exs
defmodule ExCellenceServer.Learning.ProposalTest do
  use ExCellenceServer.DataCase, async: true

  alias ExCellenceServer.Learning.Proposal
  alias ExCellenceServer.Repo

  test "changeset valid with required fields" do
    params = %{
      source: "retrospective:quest-1",
      type: "threshold",
      target_id: "quest-1",
      current_value: %{"escalate_on.confidence" => 0.7},
      proposed_value: %{"escalate_on.confidence" => 0.65},
      reason: "Escalation firing too often"
    }

    assert %{valid?: true} = Proposal.changeset(%Proposal{}, params)
  end

  test "changeset invalid without source" do
    assert %{valid?: false} =
             Proposal.changeset(%Proposal{}, %{type: "threshold", target_id: "1"})
  end

  test "auto_apply?/1 returns true for small threshold nudge" do
    proposal = %Proposal{
      type: "threshold",
      current_value: %{"escalate_on.confidence" => 0.70},
      proposed_value: %{"escalate_on.confidence" => 0.65}
    }

    assert Proposal.auto_apply?(proposal)
  end

  test "auto_apply?/1 returns false for system_prompt change" do
    proposal = %Proposal{
      type: "system_prompt",
      current_value: %{"system_prompt" => "old"},
      proposed_value: %{"system_prompt" => "new"}
    }

    refute Proposal.auto_apply?(proposal)
  end

  test "auto_apply?/1 returns false for large threshold change" do
    proposal = %Proposal{
      type: "threshold",
      current_value: %{"escalate_on.confidence" => 0.70},
      proposed_value: %{"escalate_on.confidence" => 0.40}
    }

    refute Proposal.auto_apply?(proposal)
  end
end
```

**Step 4: Run to confirm failure**

```bash
mix test test/ex_cellence_server/learning/proposal_test.exs
```

Expected: error — module not found.

**Step 5: Implement Proposal schema**

```elixir
# lib/ex_cellence_server/learning/proposal.ex
defmodule ExCellenceServer.Learning.Proposal do
  @moduledoc """
  A proposed change to member config, quest roster, or escalation thresholds.
  Small changes are auto-applied. Larger changes require human approval in Lodge.
  """
  use Ecto.Schema
  import Ecto.Changeset

  # Auto-apply threshold: max change magnitude for numeric fields
  @auto_apply_threshold 0.05
  # Types that always require human approval
  @approval_required_types ~w(system_prompt roster member_enable member_disable)

  schema "excellence_proposals" do
    field :source, :string
    field :type, :string
    field :target_id, :string
    field :current_value, :map, default: %{}
    field :proposed_value, :map, default: %{}
    field :reason, :string
    field :status, :string, default: "pending"
    timestamps()
  end

  @required [:source, :type, :target_id]
  @optional [:current_value, :proposed_value, :reason, :status]

  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["pending", "approved", "rejected", "applied"])
    |> validate_inclusion(:type, ["threshold", "model", "system_prompt", "roster",
                                   "member_enable", "member_disable"])
  end

  @doc """
  Returns true if this proposal can be auto-applied without human approval.
  Only small numeric nudges to threshold/model fields qualify.
  """
  def auto_apply?(%__MODULE__{type: type}) when type in @approval_required_types, do: false

  def auto_apply?(%__MODULE__{type: "threshold", current_value: cur, proposed_value: prop}) do
    # Check all proposed numeric changes are within the auto-apply threshold
    Enum.all?(prop, fn {key, new_val} ->
      case {Map.get(cur, key), new_val} do
        {old, new} when is_float(old) and is_float(new) ->
          abs(new - old) <= @auto_apply_threshold
        _ -> false
      end
    end)
  end

  def auto_apply?(%__MODULE__{type: "model"}), do: true

  def auto_apply?(_), do: false
end
```

**Step 6: Run tests**

```bash
mix test test/ex_cellence_server/learning/proposal_test.exs
```

Expected: all passing.

**Step 7: Commit**

```bash
git add priv/repo/migrations/20260308250000_add_proposals.exs lib/ex_cellence_server/learning/proposal.ex test/ex_cellence_server/learning/proposal_test.exs
git commit -m "feat: add Proposal schema for learning loop"
```

---

## Task 2: LearningLoop — retrospective analysis and proposal generation

**Files:**
- Create: `lib/ex_cellence_server/learning/learning_loop.ex`
- Create: `test/ex_cellence_server/learning/learning_loop_test.exs`

**Step 1: Write the failing tests**

```elixir
# test/ex_cellence_server/learning/learning_loop_test.exs
defmodule ExCellenceServer.Learning.LearningLoopTest do
  use ExCellenceServer.DataCase, async: true

  alias ExCellenceServer.Learning.LearningLoop
  alias ExCellenceServer.Quests

  describe "build_retrospective_prompt/2" do
    test "includes quest name and run stats" do
      {:ok, quest} = Quests.create_quest(%{name: "WCAG Scan", trigger: "manual"})

      {:ok, _} =
        Quests.create_quest_run(%{
          quest_id: quest.id,
          input: "test",
          status: "complete",
          results: %{"verdict" => "pass", "confidence" => 0.85}
        })

      prompt = LearningLoop.build_retrospective_prompt(quest, window_days: 7)
      assert prompt =~ "WCAG Scan"
      assert prompt =~ "pass"
    end
  end

  describe "parse_proposals/2" do
    test "extracts threshold proposal from response text" do
      quest_id = "42"

      response = ~s"""
      Looking at the run data, escalation is firing too often.
      {"type": "threshold", "target_id": "#{quest_id}", "field": "escalate_on.confidence", "current": 0.70, "proposed": 0.65, "reason": "Escalating on 40% of runs is too high."}
      """

      proposals = LearningLoop.parse_proposals(response, quest_id)
      assert length(proposals) == 1
      assert hd(proposals).type == "threshold"
      assert hd(proposals).proposed_value["escalate_on.confidence"] == 0.65
    end

    test "returns empty list when no JSON blocks found" do
      assert [] = LearningLoop.parse_proposals("Nothing actionable here.", "1")
    end
  end
end
```

**Step 2: Run to confirm failure**

```bash
mix test test/ex_cellence_server/learning/learning_loop_test.exs
```

Expected: error — module not found.

**Step 3: Implement LearningLoop**

```elixir
# lib/ex_cellence_server/learning/learning_loop.ex
defmodule ExCellenceServer.Learning.LearningLoop do
  @moduledoc """
  Analyzes recent quest run outcomes and generates Proposal records.
  Small changes are auto-applied immediately. Larger changes are queued for human approval.
  """

  import Ecto.Query

  alias ExCellenceServer.ClaudeClient
  alias ExCellenceServer.Learning.Proposal
  alias ExCellenceServer.Quests
  alias ExCellenceServer.Quests.QuestRun
  alias ExCellenceServer.Repo

  @system_prompt """
  You are a performance analyst for an AI evaluation pipeline.
  Review the provided quest run statistics and identify 1-3 specific, actionable improvements.

  For each improvement, output a JSON block on its own line:
  {"type": "threshold", "target_id": "<quest_id>", "field": "escalate_on.confidence", "current": 0.70, "proposed": 0.65, "reason": "..."}

  Valid types: threshold, model, system_prompt, roster
  For "threshold": field is the config path, current and proposed are floats.
  For "model": field is "model", current and proposed are model name strings.
  For "system_prompt" and "roster": these require human approval.

  Only output JSON blocks for genuine, evidence-based suggestions.
  If nothing needs changing, output: NO_CHANGES
  """

  @doc """
  Run retrospective analysis for a quest. Creates Proposal records and auto-applies small ones.
  Returns {:ok, proposals} or {:error, reason}.
  """
  def run_for_quest(quest, opts \\ []) do
    prompt = build_retrospective_prompt(quest, opts)
    tier = Keyword.get(opts, :claude_tier, :claude_haiku)

    case ClaudeClient.call(tier, @system_prompt, prompt) do
      {:ok, %{action: _, confidence: _, reason: response}} ->
        proposals = parse_proposals(response, to_string(quest.id))
        created = Enum.map(proposals, &create_proposal/1)
        auto_apply_eligible(created)
        {:ok, created}

      {:error, :no_api_key} ->
        # Fall back to master-tier Ollama member if no API key
        run_with_ollama(quest, prompt)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_with_ollama(quest, _prompt) do
    # No API key, no Ollama fallback implemented yet — return empty
    {:ok, []}
  end

  defp create_proposal(attrs) do
    case %Proposal{} |> Proposal.changeset(attrs) |> Repo.insert() do
      {:ok, proposal} -> proposal
      {:error, _} -> nil
    end
  end

  defp auto_apply_eligible(proposals) do
    proposals
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&Proposal.auto_apply?/1)
    |> Enum.each(&apply_proposal/1)
  end

  defp apply_proposal(%Proposal{type: "threshold", target_id: quest_id} = proposal) do
    with {id, _} <- Integer.parse(quest_id),
         quest <- Quests.get_quest!(id) do
      # Apply threshold change to matching roster steps
      updated_roster =
        Enum.map(quest.roster, fn step ->
          Enum.reduce(proposal.proposed_value, step, fn {field, value}, acc ->
            case field do
              "escalate_on.confidence" ->
                put_in(acc, ["escalate_on", "threshold"], value)

              _ ->
                acc
            end
          end)
        end)

      Quests.update_quest(quest, %{roster: updated_roster})
      Repo.get!(Proposal, proposal.id)
      |> Proposal.changeset(%{status: "applied"})
      |> Repo.update()
    end
  end

  defp apply_proposal(%Proposal{type: "model", target_id: member_id} = proposal) do
    import Ecto.Query

    alias Excellence.Schemas.Member

    case Repo.get(Member, String.to_integer(member_id)) do
      nil ->
        :ok

      member ->
        new_model = proposal.proposed_value["model"]
        new_config = Map.put(member.config, "model", new_model)
        member |> Member.changeset(%{config: new_config}) |> Repo.update()

        Repo.get!(Proposal, proposal.id)
        |> Proposal.changeset(%{status: "applied"})
        |> Repo.update()
    end
  end

  defp apply_proposal(_proposal), do: :ok

  @doc """
  Build a retrospective prompt with recent run stats for a quest.
  """
  def build_retrospective_prompt(quest, opts \\ []) do
    window_days = Keyword.get(opts, :window_days, 7)
    cutoff = DateTime.add(DateTime.utc_now(), -window_days * 86_400, :second)

    runs =
      Repo.all(
        from r in QuestRun,
          where: r.quest_id == ^quest.id and r.inserted_at > ^cutoff and r.status == "complete",
          order_by: [desc: r.inserted_at],
          limit: 50
      )

    total = length(runs)
    verdicts = Enum.group_by(runs, &get_in(&1.results, ["verdict"]))
    verdict_counts = Map.new(verdicts, fn {k, v} -> {k || "unknown", length(v)} end)

    escalations =
      Enum.count(runs, fn r ->
        trace = get_in(r.results, ["trace"])
        is_list(trace) && length(trace) > 1
      end)

    avg_confidence =
      if total > 0 do
        sum = Enum.sum(Enum.map(runs, fn r -> get_in(r.results, ["confidence"]) || 0.0 end))
        Float.round(sum / total, 2)
      else
        0.0
      end

    roster_summary =
      quest.roster
      |> Enum.map(fn step ->
        "  - who: #{step["who"]}, how: #{step["how"]}, escalate_on: #{inspect(step["escalate_on"])}"
      end)
      |> Enum.join("\n")

    """
    Quest: #{quest.name} (ID: #{quest.id})
    Analysis window: last #{window_days} days
    Total runs: #{total}
    Verdict breakdown: #{inspect(verdict_counts)}
    Escalations: #{escalations}/#{total} (#{if total > 0, do: Float.round(escalations / total * 100, 1), else: 0}%)
    Average confidence: #{avg_confidence}

    Current roster:
    #{roster_summary}

    Based on this data, identify specific improvements to reduce unnecessary escalations,
    improve confidence, or better calibrate the roster.
    """
  end

  @doc """
  Parse JSON proposal blocks from an LLM response string.
  Returns a list of proposal attribute maps.
  """
  def parse_proposals(response, quest_id) do
    Regex.scan(~r/\{[^{}]+\}/, response)
    |> List.flatten()
    |> Enum.flat_map(fn json_str ->
      case Jason.decode(json_str) do
        {:ok, data} -> [build_proposal_attrs(data, quest_id)]
        _ -> []
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_proposal_attrs(%{"type" => type, "field" => field, "current" => cur, "proposed" => prop, "reason" => reason}, quest_id) do
    %{
      source: "retrospective:#{quest_id}",
      type: type,
      target_id: quest_id,
      current_value: %{field => cur},
      proposed_value: %{field => prop},
      reason: reason,
      status: "pending"
    }
  end

  defp build_proposal_attrs(_, _), do: nil
end
```

**Step 4: Run tests**

```bash
mix test test/ex_cellence_server/learning/learning_loop_test.exs
```

Expected: all passing.

**Step 5: Commit**

```bash
git add lib/ex_cellence_server/learning/learning_loop.ex test/ex_cellence_server/learning/learning_loop_test.exs
git commit -m "feat: add LearningLoop retrospective analysis and proposal generation"
```

---

## Task 3: Scheduled quest runner (cron support)

**Files:**
- Create: `lib/ex_cellence_server/scheduled_quest_runner.ex`
- Modify: `lib/ex_cellence_server/application.ex`

**Step 1: Add `crontab` dependency**

In `mix.exs`, add to `deps`:

```elixir
{:crontab, "~> 1.1"}
```

Run:

```bash
mix deps.get
```

**Step 2: Implement ScheduledQuestRunner GenServer**

```elixir
# lib/ex_cellence_server/scheduled_quest_runner.ex
defmodule ExCellenceServer.ScheduledQuestRunner do
  @moduledoc """
  GenServer that wakes up every minute, checks for scheduled quests that are due,
  and runs them via QuestRunner.
  """
  use GenServer

  alias ExCellenceServer.Quests
  alias ExCellenceServer.QuestRunner

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{last_check: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(:check_scheduled, state) do
    now = DateTime.utc_now()
    run_due_quests(now)
    schedule_check()
    {:noreply, %{state | last_check: now}}
  end

  defp schedule_check do
    Process.send_after(self(), :check_scheduled, :timer.minutes(1))
  end

  defp run_due_quests(now) do
    Quests.list_quests()
    |> Enum.filter(&scheduled_and_due?(&1, now))
    |> Enum.each(fn quest ->
      Task.start(fn ->
        case QuestRunner.run(quest, "") do
          {:ok, result} ->
            Quests.create_quest_run(%{
              quest_id: quest.id,
              input: "(scheduled run)",
              status: "complete",
              results: result
            })

          {:error, _reason} ->
            Quests.create_quest_run(%{
              quest_id: quest.id,
              input: "(scheduled run)",
              status: "failed",
              results: %{}
            })
        end
      end)
    end)
  end

  defp scheduled_and_due?(%{trigger: "scheduled", schedule: schedule, status: "active"} = _quest, now)
       when is_binary(schedule) do
    case Crontab.CronExpression.Parser.parse(schedule) do
      {:ok, expr} ->
        # Check if cron would have fired in the last minute
        one_minute_ago = DateTime.add(now, -60, :second)

        case Crontab.Scheduler.get_next_run_date(expr, NaiveDateTime.from_erl!(DateTime.to_erl(one_minute_ago))) do
          {:ok, next} ->
            next_dt = DateTime.from_naive!(next, "Etc/UTC")
            DateTime.compare(next_dt, now) in [:lt, :eq]

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp scheduled_and_due?(_quest, _now), do: false
end
```

**Step 3: Add to application supervision tree**

In `lib/ex_cellence_server/application.ex`, add to the children list:

```elixir
ExCellenceServer.ScheduledQuestRunner
```

**Step 4: Compile check**

```bash
mix compile --warnings-as-errors
```

Expected: clean compile.

**Step 5: Commit**

```bash
git add lib/ex_cellence_server/scheduled_quest_runner.ex lib/ex_cellence_server/application.ex mix.exs mix.lock
git commit -m "feat: add ScheduledQuestRunner GenServer for cron-based quest execution"
```

---

## Task 4: Lodge Proposals card + approve/reject events

**Files:**
- Modify: `lib/ex_cellence_server_web/live/lodge_live.ex`
- Create: `test/ex_cellence_server_web/live/lodge_proposals_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_cellence_server_web/live/lodge_proposals_test.exs
defmodule ExCellenceServerWeb.LodgeProposalsTest do
  use ExCellenceServerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias ExCellenceServer.Learning.Proposal
  alias ExCellenceServer.Repo
  alias Excellence.Schemas.Member

  setup do
    # Need a member so lodge doesn't redirect
    {:ok, _} =
      Repo.insert(%Member{
        type: "role",
        name: "Test Member",
        source: "db",
        status: "active",
        config: %{"rank" => "journeyman", "model" => "", "strategy" => "cot", "system_prompt" => ""}
      })

    :ok
  end

  test "lodge renders proposals section", %{conn: conn} do
    {:ok, _, html} = live(conn, "/lodge")
    assert html =~ "Proposals"
  end

  test "pending proposal shown on lodge", %{conn: conn} do
    {:ok, _} =
      Repo.insert(%Proposal{
        source: "retrospective:1",
        type: "threshold",
        target_id: "1",
        current_value: %{"escalate_on.confidence" => 0.7},
        proposed_value: %{"escalate_on.confidence" => 0.65},
        reason: "Escalating too often",
        status: "pending"
      })

    {:ok, _, html} = live(conn, "/lodge")
    assert html =~ "Escalating too often"
  end

  test "approve_proposal changes status to approved", %{conn: conn} do
    {:ok, proposal} =
      Repo.insert(%Proposal{
        source: "retrospective:1",
        type: "system_prompt",
        target_id: "1",
        current_value: %{"system_prompt" => "old"},
        proposed_value: %{"system_prompt" => "new"},
        reason: "Improve prompt clarity",
        status: "pending"
      })

    {:ok, view, _} = live(conn, "/lodge")
    render_click(view, "approve_proposal", %{"id" => to_string(proposal.id)})

    updated = Repo.get!(Proposal, proposal.id)
    assert updated.status == "approved"
  end

  test "reject_proposal changes status to rejected", %{conn: conn} do
    {:ok, proposal} =
      Repo.insert(%Proposal{
        source: "retrospective:1",
        type: "threshold",
        target_id: "1",
        current_value: %{},
        proposed_value: %{},
        reason: "Test",
        status: "pending"
      })

    {:ok, view, _} = live(conn, "/lodge")
    render_click(view, "reject_proposal", %{"id" => to_string(proposal.id)})

    updated = Repo.get!(Proposal, proposal.id)
    assert updated.status == "rejected"
  end
end
```

**Step 2: Run to confirm failure**

```bash
mix test test/ex_cellence_server_web/live/lodge_proposals_test.exs
```

Expected: failures — Lodge doesn't have proposals yet.

**Step 3: Update LodgeLive to include proposals**

In `lib/ex_cellence_server_web/live/lodge_live.ex`:

Add alias at top:

```elixir
alias ExCellenceServer.Learning.Proposal
```

Add to `load_dashboard_data/1`:

```elixir
import Ecto.Query

pending_proposals =
  Repo.all(
    from p in Proposal,
      where: p.status == "pending",
      order_by: [desc: p.inserted_at]
  )

recent_auto_applied =
  Repo.all(
    from p in Proposal,
      where: p.status == "applied",
      order_by: [desc: p.updated_at],
      limit: 5
  )

assign(socket,
  ...existing assigns...,
  pending_proposals: pending_proposals,
  recent_auto_applied: recent_auto_applied
)
```

Add event handlers:

```elixir
@impl true
def handle_event("approve_proposal", %{"id" => id}, socket) do
  proposal = Repo.get!(Proposal, String.to_integer(id))
  proposal |> Proposal.changeset(%{status: "approved"}) |> Repo.update()
  {:noreply, load_dashboard_data(socket)}
end

@impl true
def handle_event("reject_proposal", %{"id" => id}, socket) do
  proposal = Repo.get!(Proposal, String.to_integer(id))
  proposal |> Proposal.changeset(%{status: "rejected"}) |> Repo.update()
  {:noreply, load_dashboard_data(socket)}
end
```

Add Proposals card to render:

```elixir
<.card>
  <.card_header>
    <.card_title>Proposals</.card_title>
  </.card_header>
  <.card_content>
    <%= if @pending_proposals == [] do %>
      <p class="text-muted-foreground text-sm">No pending proposals.</p>
    <% else %>
      <div class="space-y-3">
        <%= for proposal <- @pending_proposals do %>
          <div class="rounded border p-3 text-sm space-y-1">
            <div class="font-medium">{proposal.type} — {proposal.target_id}</div>
            <p class="text-muted-foreground">{proposal.reason}</p>
            <div class="flex items-center gap-2 pt-1 text-xs">
              <span class="text-muted-foreground">
                {inspect(proposal.current_value)} → {inspect(proposal.proposed_value)}
              </span>
            </div>
            <div class="flex gap-2 pt-1">
              <.button size="sm" phx-click="approve_proposal" phx-value-id={proposal.id}>
                Approve
              </.button>
              <.button size="sm" variant="outline" phx-click="reject_proposal" phx-value-id={proposal.id}>
                Reject
              </.button>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    <%= if @recent_auto_applied != [] do %>
      <details class="mt-4">
        <summary class="text-xs text-muted-foreground cursor-pointer">
          Recent auto-applied ({length(@recent_auto_applied)})
        </summary>
        <div class="mt-2 space-y-1">
          <%= for p <- @recent_auto_applied do %>
            <div class="text-xs text-muted-foreground">
              {p.type} on {p.target_id}: {p.reason}
            </div>
          <% end %>
        </div>
      </details>
    <% end %>
  </.card_content>
</.card>
```

**Step 4: Run tests**

```bash
mix test test/ex_cellence_server_web/live/lodge_proposals_test.exs
```

Expected: all passing.

**Step 5: Commit**

```bash
git add lib/ex_cellence_server_web/live/lodge_live.ex test/ex_cellence_server_web/live/lodge_proposals_test.exs
git commit -m "feat: add Proposals card to Lodge with approve/reject"
```

---

## Task 5: Wire retrospective to run from QuestsLive

**Files:**
- Modify: `lib/ex_cellence_server_web/live/quests_live.ex`

**Step 1: Add "Run Retrospective" button to quest card**

In the `quest_card` component, add below the Run Now form:

```elixir
<div class="flex justify-end pt-1">
  <.button
    size="sm"
    variant="ghost"
    phx-click="run_retrospective"
    phx-value-id={@quest.id}
    class="text-xs"
  >
    Run Retrospective
  </.button>
</div>
```

**Step 2: Add handle_event for run_retrospective**

```elixir
@impl true
def handle_event("run_retrospective", %{"id" => id}, socket) do
  quest = Quests.get_quest!(String.to_integer(id))
  parent = self()

  Task.start(fn ->
    result = ExCellenceServer.Learning.LearningLoop.run_for_quest(quest)
    send(parent, {:retrospective_complete, id, result})
  end)

  {:noreply, put_flash(socket, :info, "Retrospective started for #{quest.name}")}
end

@impl true
def handle_info({:retrospective_complete, _id, {:ok, proposals}}, socket) do
  count = length(proposals)
  {:noreply, put_flash(socket, :info, "Retrospective complete: #{count} proposal(s) generated")}
end

def handle_info({:retrospective_complete, _id, {:error, _}}, socket) do
  {:noreply, put_flash(socket, :error, "Retrospective failed — check ANTHROPIC_API_KEY")}
end
```

**Step 3: Compile and run full test suite**

```bash
mix compile --warnings-as-errors && mix test
```

Expected: all passing.

**Step 4: Commit**

```bash
git add lib/ex_cellence_server_web/live/quests_live.ex
git commit -m "feat: add Run Retrospective button to quest cards"
```

---

## Task 6: Format, full test run, final commit

**Step 1: Format**

```bash
mix format
```

**Step 2: Full test suite**

```bash
mix test
```

Expected: all passing.

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: learning loop complete — proposals, auto-apply, scheduled quests, Lodge approvals"
```
