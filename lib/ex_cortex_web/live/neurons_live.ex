defmodule ExCortexWeb.NeuronsLive do
  @moduledoc "Team and agent management screen — clusters (clusters) and their neurons (neurons)."
  use ExCortexWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias ExCortex.Clusters
  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo

  @impl true
  def mount(_params, _session, socket) do
    clusters = load_clusters()
    neurons = load_neurons()

    {:ok,
     assign(socket,
       page_title: "Neurons",
       clusters: clusters,
       neurons: neurons,
       expanded_clusters: MapSet.new(),
       selected_cluster: nil,
       selected_neuron: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_cluster", %{"cluster" => guild_name}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded_clusters, guild_name),
        do: MapSet.delete(socket.assigns.expanded_clusters, guild_name),
        else: MapSet.put(socket.assigns.expanded_clusters, guild_name)

    {:noreply,
     assign(socket,
       expanded_clusters: expanded,
       selected_cluster: guild_name,
       selected_neuron: nil
     )}
  end

  @impl true
  def handle_event("select_neuron", %{"id" => id}, socket) do
    neuron = Repo.get(Neuron, id)
    {:noreply, assign(socket, selected_neuron: neuron)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <div class="flex flex-col gap-1">
        <h1 class="text-2xl font-bold tracking-tight t-bright">Neurons</h1>
        <p class="t-dim text-sm">
          {length(@neurons)} neurons across {length(@clusters)} clusters
        </p>
      </div>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <.panel title="CLUSTERS" class="lg:col-span-1">
          <div class="space-y-1">
            <%= if @clusters == [] do %>
              <p class="t-dim text-sm py-2">No clusters configured.</p>
            <% end %>
            <%= for cluster <- @clusters do %>
              <% cluster_neurons = neurons_for_cluster(@neurons, cluster.guild_name) %>
              <% expanded = MapSet.member?(@expanded_clusters, cluster.guild_name) %>
              <div>
                <button
                  type="button"
                  class={[
                    "w-full text-left px-2 py-1.5 text-sm flex items-center justify-between gap-2 rounded transition-colors",
                    "hover:bg-muted/40",
                    if(@selected_cluster == cluster.guild_name,
                      do: "t-cyan font-medium",
                      else: "t-bright"
                    )
                  ]}
                  phx-click="select_cluster"
                  phx-value-cluster={cluster.guild_name}
                >
                  <span class="flex items-center gap-1.5 min-w-0">
                    <span class={["transition-transform text-xs t-dim", if(expanded, do: "rotate-90")]}>
                      ▶
                    </span>
                    <span class="truncate">{cluster.guild_name}</span>
                  </span>
                  <span class="shrink-0 text-xs t-dim">{length(cluster_neurons)}</span>
                </button>

                <%= if expanded do %>
                  <div class="ml-5 mt-0.5 space-y-0.5 border-l border-border/40 pl-2">
                    <%= for neuron <- cluster_neurons do %>
                      <button
                        type="button"
                        class={[
                          "w-full text-left px-2 py-1 text-sm truncate rounded transition-colors",
                          "hover:bg-muted/40",
                          if(@selected_neuron && @selected_neuron.id == neuron.id,
                            do: "t-green font-medium",
                            else: "t-muted"
                          )
                        ]}
                        phx-click="select_neuron"
                        phx-value-id={neuron.id}
                      >
                        {neuron.name}
                      </button>
                    <% end %>
                    <%= if cluster_neurons == [] do %>
                      <p class="px-2 py-1 text-xs t-dim italic">no neurons</p>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>

            <div class="pt-2 border-t border-border/30 mt-2">
              <p class="text-xs t-dim font-medium mb-1">UNCLUSTERED</p>
              <% unclustered = unclustered_neurons(@neurons, @clusters) %>
              <%= if unclustered == [] do %>
                <p class="text-xs t-dim italic px-2">none</p>
              <% else %>
                <div class="space-y-0.5">
                  <%= for neuron <- unclustered do %>
                    <button
                      type="button"
                      class={[
                        "w-full text-left px-2 py-1 text-sm truncate rounded transition-colors",
                        "hover:bg-muted/40",
                        if(@selected_neuron && @selected_neuron.id == neuron.id,
                          do: "t-green font-medium",
                          else: "t-muted"
                        )
                      ]}
                      phx-click="select_neuron"
                      phx-value-id={neuron.id}
                    >
                      {neuron.name}
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </.panel>

        <.panel title="DETAIL" class="lg:col-span-2">
          <%= if @selected_neuron do %>
            <.neuron_detail neuron={@selected_neuron} />
          <% else %>
            <p class="t-dim text-sm py-4 text-center">Select a neuron to view details.</p>
          <% end %>
        </.panel>
      </div>
    </div>
    """
  end

  attr :neuron, Neuron, required: true

  defp neuron_detail(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h2 class="text-lg font-semibold t-bright">{@neuron.name}</h2>
          <p class="text-xs t-dim mt-0.5">
            ID #{@neuron.id} · v{@neuron.version} · source: {@neuron.source}
          </p>
        </div>
        <.status color={status_color(@neuron.status)} label={@neuron.status} />
      </div>

      <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 text-sm">
        <.detail_field label="Type" value={@neuron.type} />
        <.detail_field label="Team" value={@neuron.team || "—"} />
        <.detail_field label="Rank" value={get_in(@neuron.config, ["rank"]) || "—"} />
        <.detail_field label="Model" value={get_in(@neuron.config, ["model"]) || "—"} />
        <.detail_field label="Provider" value={get_in(@neuron.config, ["provider"]) || "—"} />
        <.detail_field label="Strategy" value={get_in(@neuron.config, ["strategy"]) || "—"} />
      </div>

      <%= if system_prompt = get_in(@neuron.config, ["system_prompt"]) do %>
        <%= if system_prompt != "" do %>
          <div>
            <p class="text-xs t-dim mb-1 font-medium">SYSTEM PROMPT</p>
            <pre class="text-xs t-muted whitespace-pre-wrap break-words border border-border/30 rounded p-3 bg-muted/20 max-h-60 overflow-y-auto">{system_prompt}</pre>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp detail_field(assigns) do
    ~H"""
    <div>
      <p class="text-xs t-dim">{@label}</p>
      <p class="t-bright font-medium truncate">{@value}</p>
    </div>
    """
  end

  defp load_clusters do
    Clusters.list_charters()
  end

  defp load_neurons do
    Repo.all(from(n in Neuron, order_by: [asc: n.team, asc: n.name]))
  end

  defp neurons_for_cluster(neurons, guild_name) do
    Enum.filter(neurons, fn n -> n.team == guild_name end)
  end

  defp unclustered_neurons(neurons, clusters) do
    cluster_names = MapSet.new(clusters, & &1.guild_name)
    Enum.filter(neurons, fn n -> is_nil(n.team) or not MapSet.member?(cluster_names, n.team) end)
  end

  defp status_color("active"), do: "green"
  defp status_color("shadow"), do: "cyan"
  defp status_color("paused"), do: "amber"
  defp status_color("archived"), do: "red"
  defp status_color(_), do: "dim"
end
