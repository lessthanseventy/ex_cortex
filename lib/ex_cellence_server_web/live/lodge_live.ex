defmodule ExCellenceServerWeb.LodgeLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import ExCellenceDashboard.Components.AgentHealth
  import ExCellenceDashboard.Components.CalibrationChart
  import ExCellenceDashboard.Components.DriftMonitor
  import ExCellenceDashboard.Components.OutcomeTracker
  import ExCellenceDashboard.Components.ReplayViewer
  import SaladUI.Card

  alias Excellence.Schemas.Decision
  alias Excellence.Schemas.Outcome
  alias Excellence.Schemas.ResourceDefinition

  @impl true
  def mount(_params, _session, socket) do
    import Ecto.Query

    has_members =
      ExCellenceServer.Repo.exists?(from(r in ResourceDefinition, where: r.type == "role"))

    if has_members do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(ExCellenceServer.PubSub, "evaluation:results")
        :timer.send_interval(30_000, self(), :refresh)
      end

      {:ok, load_dashboard_data(socket)}
    else
      {:ok, push_navigate(socket, to: "/guild-hall")}
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
      |> ExCellenceServer.Repo.all()
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
      |> ExCellenceServer.Repo.all()
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

    assign(socket,
      page_title: "Lodge",
      decisions: decisions,
      outcomes: outcomes,
      outcome_stats: outcome_stats,
      agents: [],
      drift_result: {:ok, :insufficient_data},
      calibration_buckets: []
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">Lodge</h1>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <.card>
          <.card_header>
            <.card_title>Recent Decisions</.card_title>
          </.card_header>
          <.card_content>
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
