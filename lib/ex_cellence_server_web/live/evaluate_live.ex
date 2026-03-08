defmodule ExCellenceServerWeb.EvaluateLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import ExCellenceDashboard.Components.ConsensusViz
  import ExCellenceDashboard.Components.VerdictPanel
  import SaladUI.Card

  alias ExCellenceServer.Evaluator

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCellenceServer.PubSub, "evaluation:results")
    end

    current_guild = Evaluator.current_guild()

    {:ok,
     assign(socket,
       page_title: "Evaluate",
       guild_name: current_guild && elem(current_guild, 0),
       input_text: "",
       running: false,
       verdicts: [],
       role_results: [],
       decision: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("update_input", %{"input" => text}, socket) do
    {:noreply, assign(socket, input_text: text)}
  end

  @impl true
  def handle_event("run", _params, socket) do
    input_text = socket.assigns.input_text

    if socket.assigns.guild_name && input_text != "" do
      socket =
        assign(socket, running: true, verdicts: [], role_results: [], decision: nil, error: nil)

      pid = self()

      Task.start(fn ->
        run_evaluation(input_text, pid)
      end)

      {:noreply, socket}
    else
      message =
        if socket.assigns.guild_name,
          do: "Enter input text",
          else: "Install a guild first"

      {:noreply, put_flash(socket, :error, message)}
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

  defp run_evaluation(input_text, caller_pid) do
    result =
      try do
        {:ok, Evaluator.evaluate(input_text)}
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
          <div class="flex items-center gap-2">
            <label class="text-sm font-medium">Guild:</label>
            <%= if @guild_name do %>
              <span class="text-sm">{@guild_name}</span>
            <% else %>
              <span class="text-sm text-muted-foreground">
                No guild installed. <a href="/guild-hall" class="underline">Install one</a>
              </span>
            <% end %>
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

          <.button phx-click="run" disabled={@running || !@guild_name}>
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
