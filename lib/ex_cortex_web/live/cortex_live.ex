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
         collapsed_panels: MapSet.new(),
         expanded_ruminations: MapSet.new(),
         expanded_clusters: MapSet.new(),
         expanded_engrams: MapSet.new()
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

  def handle_event("toggle_item", %{"panel" => panel, "id" => id}, socket) do
    key = String.to_existing_atom("expanded_#{panel}")
    current = Map.get(socket.assigns, key)

    updated =
      if MapSet.member?(current, id),
        do: MapSet.delete(current, id),
        else: MapSet.put(current, id)

    {:noreply, assign(socket, [{key, updated}])}
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

  # ---------------------------------------------------------------------------
  # Pane interactions — route widget actions to tools
  # ---------------------------------------------------------------------------

  def handle_event("pane_action", %{"card-id" => card_id, "action" => action} = params, socket) do
    card = Signals.get_signal!(card_id)
    handler = get_in(card.metadata, ["action_handler", action])

    case handle_pane_action(handler, card, params) do
      {:ok, message} ->
        {:noreply, socket |> put_flash(:info, message) |> load_signals()}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}

      :noop ->
        {:noreply, socket}
    end
  end

  # Toggle a checklist item via tool
  defp handle_pane_action(%{"tool" => tool_name} = handler, card, params) do
    args = build_tool_args(handler, card, params)

    tool_mod = ExCortex.Tools.Registry.resolve_by_name(tool_name)

    if tool_mod do
      case tool_mod.call(args) do
        {:ok, message} ->
          # Also update the card's local state if it's a checklist toggle
          maybe_update_checklist(card, params)
          {:ok, message}

        {:error, reason} ->
          {:error, "Tool #{tool_name} failed: #{inspect(reason)}"}
      end
    else
      {:error, "Unknown tool: #{tool_name}"}
    end
  end

  # Refresh — re-run the owning rumination
  defp handle_pane_action(%{"rumination_id" => rum_id}, _card, _params) do
    rumination = Ruminations.get_rumination!(rum_id)
    Task.start(fn -> ExCortex.Ruminations.Runner.run(rumination, "") end)
    {:ok, "Refreshing #{rumination.name}..."}
  end

  defp handle_pane_action(nil, _card, _params), do: :noop

  defp build_tool_args(%{"args_template" => template}, _card, params) do
    Enum.reduce(template, %{}, fn {key, value}, acc ->
      resolved =
        cond do
          value == "{input}" -> params["value"] || ""
          value == "{item.text}" -> params["text"] || ""
          value == "{item.index}" -> params["index"] || ""
          String.starts_with?(value, "{") -> params[String.trim(value, "{}")] || ""
          true -> value
        end

      Map.put(acc, key, resolved)
    end)
  end

  defp build_tool_args(_, _card, params), do: params

  defp maybe_update_checklist(card, %{"index" => idx_str}) when card.type == "checklist" do
    index = String.to_integer(idx_str)
    Signals.toggle_checklist_item(card, index)
  end

  defp maybe_update_checklist(_, _), do: :ok

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
          <.ruminations_panel ruminations={@ruminations} expanded={@expanded_ruminations} />
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
          <.clusters_panel
            clusters={@clusters}
            neuron_counts={@neuron_counts}
            expanded={@expanded_clusters}
            neurons={@neurons}
          />
        </.panel>

        <%!-- Panel 4: Recent Memory --%>
        <.panel
          title="Recent Memory"
          on_toggle="toggle_panel"
          toggle_value="memory"
          collapsed={MapSet.member?(@collapsed_panels, "memory")}
          summary={"#{length(@engrams)} recent engram#{if length(@engrams) != 1, do: "s"}"}
        >
          <.memory_panel engrams={@engrams} expanded={@expanded_engrams} />
        </.panel>
      </div>

      <div class="mt-4">
        <.key_hints hints={[{"r", "refresh"}, {"↑↓", "stream"}, {"q", "quit"}]} />
      </div>
    </div>
    """
  end

  # --- Panel content components (pattern-matched, expandable items) ---

  # -- Ruminations --
  attr :ruminations, :list, required: true
  attr :expanded, :any, required: true
  defp ruminations_panel(%{ruminations: []} = assigns), do: ~H[<p class="t-dim text-xs">No active ruminations.</p>]

  defp ruminations_panel(assigns) do
    ~H[<div class="space-y-0.5">
  <.rumination_row
    :for={r <- @ruminations}
    rumination={r}
    expanded={MapSet.member?(@expanded, to_string(r.id))}
  />
</div>]
  end

  attr :rumination, :map, required: true
  attr :expanded, :boolean, required: true

  defp rumination_row(%{expanded: true} = assigns) do
    ~H"""
    <div
      class="cursor-pointer hover:bg-muted/50 rounded px-1 -mx-1 py-1"
      phx-click="toggle_item"
      phx-value-panel="ruminations"
      phx-value-id={@rumination.id}
    >
      <div class="flex items-center gap-2 text-sm">
        <.status color={rumination_status_color(@rumination)} label={@rumination.name} />
        <span class="ml-auto text-xs t-dim">▾</span>
      </div>
      <div class="pl-4 mt-1 space-y-1 text-xs t-dim">
        <p>{@rumination.description}</p>
        <div class="flex gap-3 flex-wrap">
          <span>trigger: {@rumination.trigger}</span>
          <span :if={@rumination.schedule}>schedule: {@rumination.schedule}</span>
          <span>{@rumination.step_count} step{if @rumination.step_count != 1, do: "s"}</span>
        </div>
        <.rumination_last_run last_run={@rumination.last_run} />
        <.link navigate={~p"/ruminations"} class="t-cyan hover:underline">
          open in ruminations →
        </.link>
      </div>
    </div>
    """
  end

  defp rumination_row(assigns) do
    ~H"""
    <div
      class="cursor-pointer hover:bg-muted/50 rounded px-1 -mx-1 py-0.5"
      phx-click="toggle_item"
      phx-value-panel="ruminations"
      phx-value-id={@rumination.id}
    >
      <div class="flex items-center gap-2 text-sm">
        <.status color={rumination_status_color(@rumination)} label={@rumination.name} />
        <span class="t-dim text-xs">{@rumination.trigger}</span>
        <span class="ml-auto text-xs t-dim">▸</span>
      </div>
      <.rumination_last_run last_run={@rumination.last_run} />
    </div>
    """
  end

  attr :last_run, :any, required: true

  defp rumination_last_run(%{last_run: %{inserted_at: _, status: _}} = assigns) do
    ~H[<div class="pl-4 text-xs t-dim">
  last: {format_relative(@last_run.inserted_at)} · {@last_run.status}
</div>]
  end

  defp rumination_last_run(assigns), do: ~H""

  # -- Signals --
  attr :signals, :list, required: true
  attr :expanded, :any, required: true
  defp signals_panel(%{signals: []} = assigns), do: ~H[<p class="t-dim text-xs">No active signals.</p>]

  defp signals_panel(assigns) do
    pinned = Enum.filter(assigns.signals, & &1.pinned)
    unpinned = Enum.reject(assigns.signals, & &1.pinned)
    assigns = assign(assigns, pinned: pinned, unpinned: unpinned)

    ~H"""
    <div class="space-y-3">
      <%!-- Pinned panes - expanded by default, small collapse toggle --%>
      <div :if={@pinned != []} class="space-y-2">
        <.pinned_pane
          :for={signal <- @pinned}
          signal={signal}
          collapsed={MapSet.member?(@expanded, signal.id)}
        />
      </div>
      <%!-- Regular signals - collapsed by default --%>
      <div :if={@unpinned != []} class="space-y-0.5">
        <.signal_row
          :for={signal <- @unpinned}
          signal={signal}
          expanded={MapSet.member?(@expanded, signal.id)}
        />
      </div>
    </div>
    """
  end

  attr :signal, :map, required: true
  attr :collapsed, :boolean, required: true

  defp pinned_pane(%{collapsed: true} = assigns) do
    ~H"""
    <div class="rounded border border-primary/20 bg-primary/5 px-3 py-2">
      <div
        class="flex items-center justify-between cursor-pointer"
        phx-click="toggle_signal"
        phx-value-id={@signal.id}
      >
        <div class="flex items-center gap-2 text-sm font-medium">
          <span class="text-primary/60">📌</span>
          {@signal.title}
        </div>
        <span class="text-xs t-dim">▸</span>
      </div>
    </div>
    """
  end

  defp pinned_pane(assigns) do
    ~H"""
    <div class="rounded border border-primary/20 bg-primary/5 px-3 py-2">
      <div
        class="flex items-center justify-between cursor-pointer mb-2"
        phx-click="toggle_signal"
        phx-value-id={@signal.id}
      >
        <div class="flex items-center gap-2 text-sm font-medium">
          <span class="text-primary/60">📌</span>
          {@signal.title}
        </div>
        <span class="text-xs t-dim">▾</span>
      </div>
      <.signal_card card={@signal} />
    </div>
    """
  end

  attr :signal, :map, required: true
  attr :expanded, :boolean, required: true

  defp signal_row(%{expanded: true} = assigns) do
    ~H"""
    <div
      class="cursor-pointer hover:bg-muted/50 rounded px-1 -mx-1"
      phx-click="toggle_signal"
      phx-value-id={@signal.id}
    >
      <div class="flex items-start gap-2 text-sm">
        <.status color={signal_color(@signal)} label={@signal.title} />
        <span class="ml-auto text-xs t-dim">▾</span>
      </div>
      <div class="pl-4 mt-1 mb-2"><.signal_card card={@signal} /></div>
    </div>
    """
  end

  defp signal_row(assigns) do
    ~H"""
    <div
      class="cursor-pointer hover:bg-muted/50 rounded px-1 -mx-1"
      phx-click="toggle_signal"
      phx-value-id={@signal.id}
    >
      <div class="flex items-start gap-2 text-sm">
        <.status color={signal_color(@signal)} label={@signal.title} />
        <span class="ml-auto text-xs t-dim">▸</span>
      </div>
      <.signal_preview signal={@signal} />
    </div>
    """
  end

  attr :signal, :map, required: true

  defp signal_preview(%{signal: %{body: body}} = assigns) when is_binary(body) and body != "" do
    ~H[<div class="pl-4 text-xs t-dim truncate">{String.slice(@signal.body, 0, 60)}</div>]
  end

  defp signal_preview(assigns), do: ~H""

  # -- Clusters --
  attr :clusters, :list, required: true
  attr :neuron_counts, :map, required: true
  attr :expanded, :any, required: true
  attr :neurons, :list, required: true
  defp clusters_panel(%{clusters: []} = assigns), do: ~H[<p class="t-dim text-xs">No clusters installed.</p>]

  defp clusters_panel(assigns) do
    ~H"""
    <div class="space-y-0.5">
      <.cluster_row
        :for={cluster <- @clusters}
        cluster={cluster}
        count={neuron_count(@neuron_counts, cluster.cluster_name)}
        expanded={MapSet.member?(@expanded, cluster.cluster_name)}
        neurons={Enum.filter(@neurons, &(&1.team == cluster.cluster_name))}
      />
    </div>
    """
  end

  attr :cluster, :map, required: true
  attr :count, :integer, required: true
  attr :expanded, :boolean, required: true
  attr :neurons, :list, required: true

  defp cluster_row(%{expanded: true} = assigns) do
    ~H"""
    <div
      class="cursor-pointer hover:bg-muted/50 rounded px-1 -mx-1 py-1"
      phx-click="toggle_item"
      phx-value-panel="clusters"
      phx-value-id={@cluster.cluster_name}
    >
      <div class="flex items-center gap-2 text-sm">
        <.status color="green" label={@cluster.cluster_name} />
        <span class="t-dim text-xs">{@count} neurons</span>
        <span class="ml-auto text-xs t-dim">▾</span>
      </div>
      <div class="pl-4 mt-1 text-xs t-dim">
        <p :if={@cluster.pathway_text != ""} class="mb-1">
          {String.slice(@cluster.pathway_text, 0, 150)}
        </p>
        <div class="space-y-0.5">
          <div :for={neuron <- @neurons} class="flex items-center gap-2">
            <span class="t-cyan">·</span>
            <span>{neuron.name}</span>
            <span class="t-dim">({get_in(neuron.config, ["rank"]) || "—"})</span>
          </div>
        </div>
        <.link navigate={~p"/neurons"} class="t-cyan hover:underline mt-1 inline-block">
          manage neurons →
        </.link>
      </div>
    </div>
    """
  end

  defp cluster_row(assigns) do
    ~H"""
    <div
      class="cursor-pointer hover:bg-muted/50 rounded px-1 -mx-1 py-0.5"
      phx-click="toggle_item"
      phx-value-panel="clusters"
      phx-value-id={@cluster.cluster_name}
    >
      <div class="flex items-center gap-2 text-sm">
        <.status color="green" label={@cluster.cluster_name} />
        <span class="t-dim text-xs">{@count} neurons</span>
        <span class="ml-auto text-xs t-dim">▸</span>
      </div>
    </div>
    """
  end

  # -- Memory --
  attr :engrams, :list, required: true
  attr :expanded, :any, required: true
  defp memory_panel(%{engrams: []} = assigns), do: ~H[<p class="t-dim text-xs">No engrams stored.</p>]

  defp memory_panel(assigns) do
    ~H[<div class="space-y-0.5">
  <.engram_row
    :for={engram <- @engrams}
    engram={engram}
    expanded={MapSet.member?(@expanded, to_string(engram.id))}
  />
</div>]
  end

  attr :engram, :map, required: true
  attr :expanded, :boolean, required: true

  defp engram_row(%{expanded: true} = assigns) do
    ~H"""
    <div
      class="cursor-pointer hover:bg-muted/50 rounded px-1 -mx-1 py-1"
      phx-click="toggle_item"
      phx-value-panel="engrams"
      phx-value-id={@engram.id}
    >
      <div class="flex items-center gap-2 text-sm">
        <span class="t-cyan">▾</span>
        <span class="truncate">{@engram.title}</span>
      </div>
      <div class="pl-4 mt-1 space-y-1 text-xs">
        <p class="t-dim">{@engram.category} · source: {@engram.source}</p>
        <.engram_tier label="L0" content={@engram.impression} />
        <.engram_tier label="L1" content={@engram.recall} />
        <div :if={@engram.tags != []} class="flex gap-1 flex-wrap">
          <span :for={tag <- @engram.tags} class="px-1.5 py-0.5 rounded bg-muted text-xs t-dim">
            {tag}
          </span>
        </div>
        <.link navigate={~p"/memory"} class="t-cyan hover:underline inline-block">
          open in memory →
        </.link>
      </div>
    </div>
    """
  end

  defp engram_row(assigns) do
    ~H"""
    <div
      class="cursor-pointer hover:bg-muted/50 rounded px-1 -mx-1 py-0.5"
      phx-click="toggle_item"
      phx-value-panel="engrams"
      phx-value-id={@engram.id}
    >
      <div class="flex items-center gap-2 text-sm">
        <span class="t-cyan">▸</span>
        <span class="truncate">{@engram.title}</span>
      </div>
      <.engram_preview impression={@engram.impression} />
    </div>
    """
  end

  attr :impression, :string, default: nil

  defp engram_preview(%{impression: impression} = assigns) when is_binary(impression) and impression != "" do
    ~H[<div class="pl-4 text-xs t-dim truncate">{String.slice(@impression, 0, 60)}</div>]
  end

  defp engram_preview(assigns), do: ~H""

  attr :label, :string, required: true
  attr :content, :string, default: nil

  defp engram_tier(%{content: content} = assigns) when is_binary(content) and content != "" do
    ~H[<div>
  <span class="t-amber font-medium">{@label}:</span> <span class="t-dim">{@content}</span>
</div>]
  end

  defp engram_tier(assigns), do: ~H""

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

        %{
          id: rumination.id,
          name: rumination.name,
          trigger: rumination.trigger,
          schedule: rumination.schedule,
          status: rumination.status,
          step_count: length(rumination.steps || []),
          description: rumination.description,
          last_run: last_run
        }
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

    neurons = Repo.all(from(n in Neuron, where: n.type == "role", order_by: [asc: n.name]))

    neuron_counts =
      neurons
      |> Enum.group_by(& &1.team)
      |> Map.new(fn {team, members} -> {team, length(members)} end)

    assign(socket, clusters: clusters, neuron_counts: neuron_counts, neurons: neurons)
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
