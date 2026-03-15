defmodule ExCortexWeb.CortexLive do
  @moduledoc "Main monitoring dashboard — four TUI panels showing live system state."
  use ExCortexWeb, :live_view

  import Ecto.Query, only: [from: 2]
  import ExCortexWeb.Components.SignalCards, only: [signal_card: 1]

  alias ExCortex.Clusters
  alias ExCortex.Memory
  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo
  alias ExCortex.Ruminations
  alias ExCortex.Signals

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
         muse_loading: false,
         expanded_signals: MapSet.new(),
         collapsed_panels: MapSet.new()
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

  def handle_event("toggle_panel", %{"panel" => panel}, socket) do
    collapsed = socket.assigns.collapsed_panels

    collapsed =
      if MapSet.member?(collapsed, panel),
        do: MapSet.delete(collapsed, panel),
        else: MapSet.put(collapsed, panel)

    {:noreply, assign(socket, collapsed_panels: collapsed)}
  end

  def handle_event("toggle_signal", %{"id" => id}, socket) do
    signal_id = String.to_integer(id)
    expanded = socket.assigns.expanded_signals

    expanded =
      if MapSet.member?(expanded, signal_id),
        do: MapSet.delete(expanded, signal_id),
        else: MapSet.put(expanded, signal_id)

    {:noreply, assign(socket, expanded_signals: expanded)}
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
            aria-label="Ask your knowledge base"
            class="flex-1 bg-muted border border-border rounded px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-foreground"
            autocomplete="off"
            disabled={@muse_loading}
          />
          <button
            type="submit"
            class="px-4 py-2 text-sm font-medium rounded bg-primary text-primary-foreground hover:opacity-90 disabled:opacity-50"
            disabled={@muse_loading}
          >
            {if @muse_loading, do: "Thinking...", else: "Muse"}
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
        <.panel
          title="Active Ruminations"
          on_toggle="toggle_panel"
          toggle_value="ruminations"
          collapsed={MapSet.member?(@collapsed_panels, "ruminations")}
          summary={"#{length(@ruminations)} active"}
        >
          <.ruminations_panel ruminations={@ruminations} />
        </.panel>

        <%!-- Panel 2: Signals --%>
        <.panel
          title="Signals"
          on_toggle="toggle_panel"
          toggle_value="signals"
          collapsed={MapSet.member?(@collapsed_panels, "signals")}
          summary={"#{length(@signals)} signal#{if length(@signals) != 1, do: "s"}"}
        >
          <.signals_panel signals={@signals} expanded={@expanded_signals} />
        </.panel>

        <%!-- Panel 3: Cluster Health --%>
        <.panel
          title="Cluster Health"
          on_toggle="toggle_panel"
          toggle_value="clusters"
          collapsed={MapSet.member?(@collapsed_panels, "clusters")}
          summary={"#{length(@clusters)} clusters, #{Enum.sum(Map.values(@neuron_counts))} neurons"}
        >
          <.clusters_panel clusters={@clusters} neuron_counts={@neuron_counts} />
        </.panel>

        <%!-- Panel 4: Recent Memory --%>
        <.panel
          title="Recent Memory"
          on_toggle="toggle_panel"
          toggle_value="memory"
          collapsed={MapSet.member?(@collapsed_panels, "memory")}
          summary={"#{length(@engrams)} recent engram#{if length(@engrams) != 1, do: "s"}"}
        >
          <.memory_panel engrams={@engrams} />
        </.panel>
      </div>

      <div class="mt-4">
        <.key_hints hints={[{"r", "refresh"}, {"↑↓", "stream"}, {"q", "quit"}]} />
      </div>
    </div>
    """
  end

  # --- Panel content components (pattern-matched) ---

  attr :ruminations, :list, required: true

  defp ruminations_panel(%{ruminations: []} = assigns) do
    ~H"""
    <p class="t-dim text-xs">No active ruminations.</p>
    """
  end

  defp ruminations_panel(assigns) do
    ~H"""
    <div class="space-y-1">
      <.rumination_row :for={rumination <- @ruminations} rumination={rumination} />
    </div>
    """
  end

  attr :rumination, :map, required: true

  defp rumination_row(%{rumination: %{last_run: %{inserted_at: _, status: _}}} = assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-2 text-sm">
        <.status color={rumination_status_color(@rumination)} label={@rumination.name} />
        <span class="t-dim text-xs">{@rumination.trigger}</span>
      </div>
      <div class="pl-4 text-xs t-dim">
        last: {format_relative(@rumination.last_run.inserted_at)} · {@rumination.last_run.status}
      </div>
    </div>
    """
  end

  defp rumination_row(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-sm">
      <.status color={rumination_status_color(@rumination)} label={@rumination.name} />
      <span class="t-dim text-xs">{@rumination.trigger}</span>
    </div>
    """
  end

  attr :signals, :list, required: true
  attr :expanded, :any, required: true

  defp signals_panel(%{signals: []} = assigns) do
    ~H"""
    <p class="t-dim text-xs">No active signals.</p>
    """
  end

  defp signals_panel(assigns) do
    ~H"""
    <div class="space-y-1">
      <.signal_row :for={signal <- @signals} signal={signal} expanded={@expanded} />
    </div>
    """
  end

  attr :signal, :map, required: true
  attr :expanded, :any, required: true

  defp signal_row(assigns) do
    expanded = MapSet.member?(assigns.expanded, assigns.signal.id)
    assigns = assign(assigns, :is_expanded, expanded)

    ~H"""
    <div
      class="cursor-pointer hover:bg-muted/50 rounded px-1 -mx-1"
      phx-click="toggle_signal"
      phx-value-id={@signal.id}
    >
      <div class="flex items-start gap-2 text-sm">
        <.status color={signal_color(@signal)} label={@signal.title} />
        <span class="ml-auto text-xs t-dim">{if @is_expanded, do: "▾", else: "▸"}</span>
      </div>
      <.signal_row_body signal={@signal} expanded={@is_expanded} />
    </div>
    """
  end

  attr :signal, :map, required: true
  attr :expanded, :boolean, required: true

  defp signal_row_body(%{expanded: true} = assigns) do
    ~H"""
    <div class="pl-4 mt-1 mb-2">
      <.signal_card card={@signal} />
    </div>
    """
  end

  defp signal_row_body(%{signal: %{body: body}} = assigns) when is_binary(body) and body != "" do
    ~H"""
    <div class="pl-4 text-xs t-dim truncate">{String.slice(@signal.body, 0, 60)}</div>
    """
  end

  defp signal_row_body(assigns), do: ~H""

  attr :clusters, :list, required: true
  attr :neuron_counts, :map, required: true

  defp clusters_panel(%{clusters: []} = assigns) do
    ~H"""
    <p class="t-dim text-xs">No clusters installed.</p>
    """
  end

  defp clusters_panel(assigns) do
    ~H"""
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
    """
  end

  attr :engrams, :list, required: true

  defp memory_panel(%{engrams: []} = assigns) do
    ~H"""
    <p class="t-dim text-xs">No engrams stored.</p>
    """
  end

  defp memory_panel(assigns) do
    ~H"""
    <div class="space-y-1">
      <.engram_row :for={engram <- @engrams} engram={engram} />
    </div>
    """
  end

  attr :engram, :map, required: true

  defp engram_row(%{engram: %{impression: impression}} = assigns) when is_binary(impression) do
    ~H"""
    <div>
      <div class="flex items-center gap-2 text-sm">
        <span class="t-cyan">▸</span>
        <span class="truncate">{@engram.title}</span>
      </div>
      <div class="pl-4 text-xs t-dim truncate">{String.slice(@engram.impression, 0, 60)}</div>
    </div>
    """
  end

  defp engram_row(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-sm">
      <span class="t-cyan">▸</span>
      <span class="truncate">{@engram.title}</span>
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
