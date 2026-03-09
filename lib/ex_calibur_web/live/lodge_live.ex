defmodule ExCaliburWeb.LodgeLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import ExCellenceDashboard.Components.AgentHealth
  import ExCellenceDashboard.Components.CalibrationChart
  import ExCellenceDashboard.Components.DriftMonitor
  import ExCellenceDashboard.Components.OutcomeTracker
  import ExCellenceDashboard.Components.ReplayViewer
  import SaladUI.Card

  alias Excellence.Schemas.Decision
  alias Excellence.Schemas.Member
  alias Excellence.Schemas.Outcome
  alias ExCalibur.Quests
  alias ExCalibur.Quests.Proposal

  @impl true
  def mount(_params, _session, socket) do
    import Ecto.Query

    has_members =
      ExCalibur.Repo.exists?(from(r in Member, where: r.type == "role"))

    if has_members do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(ExCalibur.PubSub, "evaluation:results")
        :timer.send_interval(30_000, self(), :refresh)
      end

      {:ok, load_dashboard_data(socket)}
    else
      {:ok, push_navigate(socket, to: "/town-square")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  defp load_dashboard_data(socket) do
    import Ecto.Query

    decisions =
      from(d in Decision, order_by: [desc: d.inserted_at], limit: 20)
      |> ExCalibur.Repo.all()
      |> Enum.map(fn d ->
        %{
          action: String.to_atom(d.action || "approve"),
          confidence: d.confidence || 0.0,
          verdicts: d.verdicts || [],
          outcome: nil,
          inserted_at: d.inserted_at
        }
      end)

    outcomes =
      from(o in Outcome, order_by: [desc: o.inserted_at], limit: 20)
      |> ExCalibur.Repo.all()
      |> Enum.map(fn o ->
        %{
          decision_id: to_string(o.decision_id),
          status: o.status,
          result: o.result,
          confidence: 0.0
        }
      end)

    total_outcomes = length(outcomes)
    resolved = Enum.count(outcomes, &(&1.status == "resolved"))
    correct = Enum.count(outcomes, &get_in(&1, [:result, "correct"]))

    outcome_stats = %{
      total: total_outcomes,
      resolved: resolved,
      pending: total_outcomes - resolved,
      correct: correct,
      false_positives: 0,
      false_negatives: 0,
      success_rate: if(resolved > 0, do: correct / resolved, else: 0.0)
    }

    proposals = Quests.list_proposals(status: "pending")

    assign(socket,
      page_title: "Lodge",
      decisions: decisions,
      outcomes: outcomes,
      outcome_stats: outcome_stats,
      agents: [],
      drift_result: {:ok, :insufficient_data},
      calibration_buckets: [],
      proposals: proposals
    )
  end

  @impl true
  def handle_event("approve_proposal", %{"id" => id}, socket) do
    proposal = ExCalibur.Repo.get(Proposal, id)

    if proposal do
      Quests.approve_proposal(proposal)
    end

    {:noreply, load_dashboard_data(socket)}
  end

  @impl true
  def handle_event("reject_proposal", %{"id" => id}, socket) do
    proposal = ExCalibur.Repo.get(Proposal, id)

    if proposal do
      Quests.reject_proposal(proposal)
    end

    {:noreply, load_dashboard_data(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Lodge</h1>
        <p class="text-muted-foreground mt-1.5">
          Monitoring, decisions, and learning loop proposals.
        </p>
      </div>

      <.card>
        <.card_header>
          <.card_title>Proposals</.card_title>
          <.card_description>Suggested improvements from the learning loop</.card_description>
        </.card_header>
        <.card_content>
          <%= if @proposals == [] do %>
            <p class="text-muted-foreground text-sm">
              No pending proposals. Proposals appear here after scheduled quests complete.
            </p>
          <% else %>
            <div class="space-y-3">
              <%= for proposal <- @proposals do %>
                <div class="flex flex-col gap-3 rounded-lg border p-4 sm:flex-row sm:items-start sm:justify-between sm:gap-4">
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2 mb-1.5">
                      <span class="text-xs font-medium px-2 py-0.5 rounded-full bg-muted text-muted-foreground">
                        {proposal.type}
                      </span>
                      <span class="text-xs text-muted-foreground">
                        {proposal.quest && proposal.quest.name}
                      </span>
                    </div>
                    <p class="text-sm font-medium">{proposal.description}</p>
                    <%= if proposal.details["suggestion"] && proposal.details["suggestion"] != "" do %>
                      <p class="text-xs text-muted-foreground mt-1">
                        {proposal.details["suggestion"]}
                      </p>
                    <% end %>
                  </div>
                  <div class="flex gap-2 shrink-0 self-start sm:self-auto">
                    <.button
                      size="sm"
                      variant="outline"
                      phx-click="approve_proposal"
                      phx-value-id={proposal.id}
                    >
                      Approve
                    </.button>
                    <.button
                      size="sm"
                      variant="ghost"
                      phx-click="reject_proposal"
                      phx-value-id={proposal.id}
                    >
                      Reject
                    </.button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </.card_content>
      </.card>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <.card>
          <.card_header>
            <.card_title>Recent Decisions</.card_title>
          </.card_header>
          <.card_content class="overflow-x-auto">
            <.replay_viewer decisions={@decisions} />
          </.card_content>
        </.card>

        <.card>
          <.card_header>
            <.card_title>Agent Health</.card_title>
          </.card_header>
          <.card_content>
            <%= if @agents == [] do %>
              <p class="text-muted-foreground text-sm">
                No agent data yet. Run an evaluation to see agent health.
              </p>
            <% else %>
              <.agent_health agents={@agents} />
            <% end %>
          </.card_content>
        </.card>

        <.card>
          <.card_header>
            <.card_title>Outcomes</.card_title>
          </.card_header>
          <.card_content>
            <.outcome_tracker outcomes={@outcomes} stats={@outcome_stats} />
          </.card_content>
        </.card>

        <.card>
          <.card_header>
            <.card_title>Drift Monitor</.card_title>
          </.card_header>
          <.card_content>
            <.drift_monitor drift_result={@drift_result} />
          </.card_content>
        </.card>
      </div>

      <%= if @calibration_buckets != [] do %>
        <.card>
          <.card_header>
            <.card_title>Calibration</.card_title>
          </.card_header>
          <.card_content>
            <.calibration_chart buckets={@calibration_buckets} />
          </.card_content>
        </.card>
      <% end %>
    </div>
    """
  end
end
