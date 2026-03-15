defmodule ExCortexWeb.CortexLive do
  @moduledoc "Main monitoring dashboard — four TUI panels showing live system state."
  use ExCortexWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias ExCortex.Clusters
  alias ExCortex.Memory
  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo
  alias ExCortex.Signals
  alias ExCortex.Ruminations

  @signal_limit 10
  @engram_limit 8

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCortex.PubSub, "daydreams")
      Phoenix.PubSub.subscribe(ExCortex.PubSub, "signals")
      Phoenix.PubSub.subscribe(ExCortex.PubSub, "memory")
    end

    {:ok,
     load_data(
       assign(socket,
         page_title: "Cortex",
         muse_input: "",
         muse_answer: nil,
         muse_loading: false
       )
     )}
  end

  @impl true
  def handle_info({:daydream_updated, _}, socket), do: {:noreply, load_ruminations(socket)}
  def handle_info({:daydream_started, _}, socket), do: {:noreply, load_ruminations(socket)}
  def handle_info({:signal_posted, _}, socket), do: {:noreply, load_signals(socket)}
  def handle_info({:engram_updated, _}, socket), do: {:noreply, load_engrams(socket)}

  def handle_info({ref, {:ok, thought}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, assign(socket, muse_answer: thought.answer, muse_loading: false)}
  end

  def handle_info({ref, {:error, _reason}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, assign(socket, muse_answer: "Something went wrong — try again.", muse_loading: false)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, assign(socket, muse_answer: "Something went wrong — try again.", muse_loading: false)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("navigate", %{"key" => "r"}, socket) do
    {:noreply, load_data(socket)}
  end

  def handle_event("navigate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("quick_muse", %{"question" => q}, socket) when q != "" do
    Task.async(fn -> ExCortex.Muse.ask(q, scope: "muse") end)
    {:noreply, assign(socket, muse_input: q, muse_loading: true, muse_answer: nil)}
  end

  def handle_event("quick_muse", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="tui-screen"
      phx-window-keydown="navigate"
      phx-value-key=""
    >
      <%!-- Quick Muse Input --%>
      <div class="mb-4">
        <form phx-submit="quick_muse" class="flex items-center gap-2">
          <input
            type="text"
            name="question"
            value={@muse_input}
            placeholder="Ask your knowledge base..."
            class="flex-1 bg-muted border border-border rounded px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-foreground"
            autocomplete="off"
            disabled={@muse_loading}
          />
          <button
            type="submit"
            class="px-4 py-2 text-sm font-medium rounded bg-foreground text-background hover:opacity-90 disabled:opacity-50"
            disabled={@muse_loading}
          >
            <%= if @muse_loading, do: "Thinking...", else: "Muse" %>
          </button>
        </form>
        <%= if @muse_answer do %>
          <div class="mt-2 p-3 bg-muted rounded border border-border text-sm text-foreground">
            {@muse_answer}
            <div class="mt-2">
              <.link navigate={~p"/muse"} class="text-xs t-cyan hover:underline">
                Open in Muse &rarr;
              </.link>
            </div>
          </div>
        <% end %>
      </div>

      <div class="tui-grid-2x2">
        <%!-- Panel 1: Active Ruminations --%>
        <.panel title="Active Ruminations">
          <%= if @ruminations == [] do %>
            <p class="t-dim text-xs">No active ruminations.</p>
          <% else %>
            <div class="space-y-1">
              <%= for rumination <- @ruminations do %>
                <div class="flex items-center gap-2 text-sm">
                  <.status color={rumination_status_color(rumination)} label={rumination.name} />
                  <span class="t-dim text-xs">{rumination.trigger}</span>
                </div>
                <%= if rumination[:last_run] do %>
                  <div class="pl-4 text-xs t-dim">
                    last: {format_relative(rumination.last_run.inserted_at)} · {rumination.last_run.status}
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </.panel>

        <%!-- Panel 2: Signals --%>
        <.panel title="Signals">
          <%= if @signals == [] do %>
            <p class="t-dim text-xs">No active signals.</p>
          <% else %>
            <div class="space-y-1">
              <%= for signal <- @signals do %>
                <div class="flex items-start gap-2 text-sm">
                  <.status color={signal_color(signal)} label={signal.title} />
                </div>
                <%= if signal.body && signal.body != "" do %>
                  <div class="pl-4 text-xs t-dim truncate">{String.slice(signal.body, 0, 60)}</div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </.panel>

        <%!-- Panel 3: Cluster Health --%>
        <.panel title="Cluster Health">
          <%= if @clusters == [] do %>
            <p class="t-dim text-xs">No clusters installed.</p>
          <% else %>
            <div class="space-y-1">
              <%= for cluster <- @clusters do %>
                <div class="flex items-center gap-2 text-sm">
                  <.status color="green" label={cluster.cluster_name} />
                  <span class="t-dim text-xs">
                    {neuron_count(@neuron_counts, cluster.cluster_name)} neurons
                  </span>
                </div>
              <% end %>
            </div>
          <% end %>
        </.panel>

        <%!-- Panel 4: Recent Memory --%>
        <.panel title="Recent Memory">
          <%= if @engrams == [] do %>
            <p class="t-dim text-xs">No engrams stored.</p>
          <% else %>
            <div class="space-y-1">
              <%= for engram <- @engrams do %>
                <div class="flex items-center gap-2 text-sm">
                  <span class="t-cyan">▸</span>
                  <span class="truncate">{engram.title}</span>
                </div>
                <%= if engram.impression do %>
                  <div class="pl-4 text-xs t-dim truncate">
                    {String.slice(engram.impression, 0, 60)}
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </.panel>
      </div>

      <div class="mt-4">
        <.key_hints hints={[{"r", "refresh"}, {"↑↓", "stream"}, {"q", "quit"}]} />
      </div>
    </div>
    """
  end

  # --- Data loading ---

  defp load_data(socket) do
    socket
    |> load_ruminations()
    |> load_signals()
    |> load_clusters()
    |> load_engrams()
  end

  defp load_ruminations(socket) do
    ruminations =
      Ruminations.list_ruminations()
      |> Enum.filter(&(&1.status == "active"))
      |> Enum.map(fn rumination ->
        last_run = rumination |> Ruminations.list_daydreams() |> List.first()
        %{id: rumination.id, name: rumination.name, trigger: rumination.trigger, last_run: last_run}
      end)

    assign(socket, ruminations: ruminations)
  end

  defp load_signals(socket) do
    signals =
      []
      |> Signals.list_signals()
      |> Enum.take(@signal_limit)

    assign(socket, signals: signals)
  end

  defp load_clusters(socket) do
    clusters = Clusters.list_pathways()

    neuron_counts =
      from(n in Neuron,
        where: n.type == "role",
        select: {n.team, count(n.id)},
        group_by: n.team
      )
      |> Repo.all()
      |> Map.new()

    assign(socket, clusters: clusters, neuron_counts: neuron_counts)
  end

  defp load_engrams(socket) do
    engrams =
      [sort: "newest"]
      |> Memory.list_engrams()
      |> Enum.take(@engram_limit)

    assign(socket, engrams: engrams)
  end

  # --- Helpers ---

  defp rumination_status_color(%{last_run: nil}), do: "dim"

  defp rumination_status_color(%{last_run: %{status: "running"}}), do: "amber"

  defp rumination_status_color(%{last_run: %{status: "complete"}}), do: "green"

  defp rumination_status_color(%{last_run: %{status: "failed"}}), do: "red"

  defp rumination_status_color(_), do: "dim"

  defp signal_color(%{type: "alert"}), do: "red"
  defp signal_color(%{type: "augury"}), do: "pink"
  defp signal_color(%{type: "proposal"}), do: "amber"
  defp signal_color(%{pinned: true}), do: "cyan"
  defp signal_color(_), do: "green"

  defp neuron_count(counts, cluster_name), do: Map.get(counts, cluster_name, 0)

  defp format_relative(nil), do: "never"

  defp format_relative(%NaiveDateTime{} = dt) do
    diff = NaiveDateTime.diff(NaiveDateTime.utc_now(), dt, :second)
    format_seconds(diff)
  end

  defp format_relative(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)
    format_seconds(diff)
  end

  defp format_seconds(diff) do
    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end
