defmodule ExCellenceServerWeb.EvaluateLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import ExCellenceDashboard.Components.ConsensusViz
  import ExCellenceDashboard.Components.VerdictPanel
  import SaladUI.Card

  alias ExCellenceServer.Evaluator

  @charter_keys %{
    "content_moderation" => "Content Moderation",
    "code_review" => "Code Review",
    "risk_assessment" => "Risk Assessment"
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCellenceServer.PubSub, "evaluation:results")
    end

    charters =
      Enum.map(@charter_keys, fn {key, guild_name} ->
        {key, "#{guild_name} Guild"}
      end)

    {:ok,
     assign(socket,
       page_title: "Evaluate",
       charters: charters,
       selected_charter: nil,
       input_text: "",
       running: false,
       verdicts: [],
       role_results: [],
       decision: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("select_charter", %{"charter" => key}, socket) do
    {:noreply, assign(socket, selected_charter: key)}
  end

  @impl true
  def handle_event("update_input", %{"input" => text}, socket) do
    {:noreply, assign(socket, input_text: text)}
  end

  @impl true
  def handle_event("run", _params, socket) do
    charter_key = socket.assigns.selected_charter
    input_text = socket.assigns.input_text

    if charter_key && input_text != "" do
      socket = assign(socket, running: true, verdicts: [], role_results: [], decision: nil, error: nil)
      pid = self()

      Task.start(fn ->
        run_evaluation(charter_key, input_text, pid)
      end)

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Select a guild and enter input text")}
    end
  end

  @impl true
  def handle_info({:evaluation_complete, result}, socket) do
    case result do
      {:ok, {action, details}} ->
        {:noreply,
         assign(socket,
           running: false,
           verdicts: details[:verdicts] || [],
           role_results: details[:role_results] || [],
           decision: %{
             action: action,
             confidence: details[:confidence] || 0.0,
             escalated: details[:escalated] || false,
             guard_blocked: details[:guard_blocked] || false
           }
         )}

      {:error, reason} ->
        {:noreply, assign(socket, running: false, error: inspect(reason))}
    end
  end

  @impl true
  def handle_info({:verdict_received, verdict}, socket) do
    {:noreply, assign(socket, verdicts: socket.assigns.verdicts ++ [verdict])}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp run_evaluation(charter_key, input_text, caller_pid) do
    guild_name = Map.fetch!(@charter_keys, charter_key)

    result =
      try do
        {:ok, Evaluator.evaluate(guild_name, input_text)}
      rescue
        e -> {:error, e}
      end

    send(caller_pid, {:evaluation_complete, result})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">Evaluate</h1>

      <.card>
        <.card_content class="pt-6 space-y-4">
          <div>
            <label class="text-sm font-medium">Guild</label>
            <div class="flex gap-2 mt-2">
              <%= for {key, name} <- @charters do %>
                <.button
                  variant={if @selected_charter == key, do: "default", else: "outline"}
                  phx-click="select_charter"
                  phx-value-charter={key}
                >
                  {name}
                </.button>
              <% end %>
            </div>
          </div>

          <div>
            <label class="text-sm font-medium">Input</label>
            <textarea
              class="mt-2 w-full rounded-md border bg-background px-3 py-2 text-sm min-h-[120px]"
              phx-change="update_input"
              name="input"
              placeholder="Enter text to evaluate..."
            ><%= @input_text %></textarea>
          </div>

          <.button phx-click="run" disabled={@running}>
            {if @running, do: "Running...", else: "Run"}
          </.button>
        </.card_content>
      </.card>

      <%= if @error do %>
        <.card>
          <.card_content class="pt-6">
            <p class="text-destructive">{@error}</p>
          </.card_content>
        </.card>
      <% end %>

      <%= if @verdicts != [] do %>
        <.verdict_panel verdicts={@verdicts} />
      <% end %>

      <%= if @decision do %>
        <.consensus_viz role_results={@role_results} decision={@decision} />
      <% end %>
    </div>
    """
  end
end
