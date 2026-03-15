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
       selected_neuron: nil,
       editing: false,
       form: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_cluster", %{"cluster" => cluster_name}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded_clusters, cluster_name),
        do: MapSet.delete(socket.assigns.expanded_clusters, cluster_name),
        else: MapSet.put(socket.assigns.expanded_clusters, cluster_name)

    {:noreply,
     assign(socket,
       expanded_clusters: expanded,
       selected_cluster: cluster_name,
       selected_neuron: nil
     )}
  end

  @impl true
  def handle_event("select_neuron", %{"id" => id}, socket) do
    neuron = Repo.get(Neuron, id)
    {:noreply, assign(socket, selected_neuron: neuron, editing: false, form: nil)}
  end

  def handle_event("edit_neuron", _params, socket) do
    neuron = socket.assigns.selected_neuron

    form_data = %{
      "name" => neuron.name,
      "team" => neuron.team || "",
      "status" => neuron.status,
      "system_prompt" => get_in(neuron.config, ["system_prompt"]) || "",
      "rank" => get_in(neuron.config, ["rank"]) || "",
      "model" => get_in(neuron.config, ["model"]) || ""
    }

    {:noreply, assign(socket, editing: true, form: to_form(form_data, as: "neuron"))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: false, form: nil)}
  end

  def handle_event("save_neuron", %{"neuron" => params}, socket) do
    neuron = socket.assigns.selected_neuron

    config =
      neuron.config
      |> Map.put("system_prompt", params["system_prompt"])
      |> Map.put("rank", params["rank"])
      |> Map.put("model", params["model"])

    attrs = %{
      name: params["name"],
      team: params["team"],
      status: params["status"],
      config: config
    }

    case Repo.update(Neuron.changeset(neuron, attrs)) do
      {:ok, updated} ->
        neurons = load_neurons()

        {:noreply,
         socket
         |> assign(selected_neuron: updated, neurons: neurons, editing: false, form: nil)
         |> put_flash(:info, "#{updated.name} updated")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Save failed: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("delete_neuron", _params, socket) do
    neuron = socket.assigns.selected_neuron

    case Repo.delete(neuron) do
      {:ok, _} ->
        neurons = load_neurons()

        {:noreply,
         socket
         |> assign(neurons: neurons, selected_neuron: nil, editing: false, form: nil)
         |> put_flash(:info, "#{neuron.name} deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Delete failed")}
    end
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
              <% cluster_neurons = neurons_for_cluster(@neurons, cluster.cluster_name) %>
              <% expanded = MapSet.member?(@expanded_clusters, cluster.cluster_name) %>
              <div>
                <button
                  type="button"
                  class={[
                    "w-full text-left px-2 py-1.5 text-sm flex items-center justify-between gap-2 rounded transition-colors",
                    "hover:bg-muted/40",
                    if(@selected_cluster == cluster.cluster_name,
                      do: "t-cyan font-medium",
                      else: "t-bright"
                    )
                  ]}
                  phx-click="select_cluster"
                  phx-value-cluster={cluster.cluster_name}
                >
                  <span class="flex items-center gap-1.5 min-w-0">
                    <span class={["transition-transform text-xs t-dim", if(expanded, do: "rotate-90")]}>
                      ▶
                    </span>
                    <span class="truncate">{cluster.cluster_name}</span>
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
          <.detail_panel
            selected_neuron={@selected_neuron}
            editing={@editing}
            form={@form}
            clusters={@clusters}
          />
        </.panel>
      </div>
    </div>
    """
  end

  # -- Detail panel: empty state, read-only, edit form --

  attr :selected_neuron, :any, required: true
  attr :editing, :boolean, required: true
  attr :form, :any, required: true
  attr :clusters, :list, required: true

  defp detail_panel(%{selected_neuron: nil} = assigns) do
    ~H"""
    <p class="t-dim text-sm py-4 text-center">Select a neuron to view details.</p>
    """
  end

  defp detail_panel(%{editing: true} = assigns) do
    ~H"""
    <form phx-submit="save_neuron" class="space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold t-bright">Editing: {@selected_neuron.name}</h2>
        <button type="button" phx-click="cancel_edit" class="text-xs t-dim hover:t-bright">
          cancel
        </button>
      </div>

      <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 text-sm">
        <div>
          <label class="text-xs t-dim block mb-1">Name</label>
          <input
            type="text"
            name="neuron[name]"
            value={@form[:name].value}
            aria-label="Name"
            class="w-full bg-muted border border-border rounded px-2 py-1.5 text-sm text-foreground"
          />
        </div>
        <div>
          <label class="text-xs t-dim block mb-1">Team</label>
          <select
            name="neuron[team]"
            aria-label="Team"
            class="w-full bg-muted border border-border rounded px-2 py-1.5 text-sm text-foreground"
          >
            <option value="">— none —</option>
            <%= for c <- @clusters do %>
              <option value={c.cluster_name} selected={@form[:team].value == c.cluster_name}>
                {c.cluster_name}
              </option>
            <% end %>
          </select>
        </div>
        <div>
          <label class="text-xs t-dim block mb-1">Status</label>
          <select
            name="neuron[status]"
            aria-label="Status"
            class="w-full bg-muted border border-border rounded px-2 py-1.5 text-sm text-foreground"
          >
            <%= for s <- ~w(draft shadow active paused archived) do %>
              <option value={s} selected={@form[:status].value == s}>{s}</option>
            <% end %>
          </select>
        </div>
        <div>
          <label class="text-xs t-dim block mb-1">Rank</label>
          <select
            name="neuron[rank]"
            aria-label="Rank"
            class="w-full bg-muted border border-border rounded px-2 py-1.5 text-sm text-foreground"
          >
            <%= for r <- ~w(apprentice journeyman master) do %>
              <option value={r} selected={@form[:rank].value == r}>{r}</option>
            <% end %>
          </select>
        </div>
        <div>
          <label class="text-xs t-dim block mb-1">Model</label>
          <input
            type="text"
            name="neuron[model]"
            value={@form[:model].value}
            aria-label="Model"
            class="w-full bg-muted border border-border rounded px-2 py-1.5 text-sm text-foreground"
          />
        </div>
      </div>

      <div>
        <label class="text-xs t-dim block mb-1">SYSTEM PROMPT</label>
        <textarea
          name="neuron[system_prompt]"
          rows="12"
          aria-label="System Prompt"
          class="w-full bg-muted border border-border rounded px-3 py-2 text-xs text-foreground font-mono whitespace-pre-wrap"
        >{@form[:system_prompt].value}</textarea>
      </div>

      <div class="flex items-center gap-2 pt-2">
        <button
          type="submit"
          class="px-4 py-1.5 text-sm font-medium rounded bg-primary text-primary-foreground hover:opacity-90"
        >
          Save
        </button>
        <button
          type="button"
          phx-click="delete_neuron"
          data-confirm="Delete this neuron?"
          class="px-4 py-1.5 text-sm font-medium rounded border border-red-500/50 text-red-400 hover:bg-red-500/10"
        >
          Delete
        </button>
      </div>
    </form>
    """
  end

  defp detail_panel(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h2 class="text-lg font-semibold t-bright">{@selected_neuron.name}</h2>
          <p class="text-xs t-dim mt-0.5">
            ID #{@selected_neuron.id} · v{@selected_neuron.version} · source: {@selected_neuron.source}
          </p>
        </div>
        <div class="flex items-center gap-2">
          <button
            type="button"
            phx-click="edit_neuron"
            class="text-xs t-cyan hover:underline"
          >
            edit
          </button>
          <.status color={status_color(@selected_neuron.status)} label={@selected_neuron.status} />
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 text-sm">
        <.detail_field label="Type" value={@selected_neuron.type} />
        <.detail_field label="Team" value={@selected_neuron.team || "—"} />
        <.detail_field label="Rank" value={get_in(@selected_neuron.config, ["rank"]) || "—"} />
        <.detail_field label="Model" value={get_in(@selected_neuron.config, ["model"]) || "—"} />
        <.detail_field label="Provider" value={get_in(@selected_neuron.config, ["provider"]) || "—"} />
        <.detail_field label="Strategy" value={get_in(@selected_neuron.config, ["strategy"]) || "—"} />
      </div>

      <%= if system_prompt = get_in(@selected_neuron.config, ["system_prompt"]) do %>
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
    Clusters.list_pathways()
  end

  defp load_neurons do
    Repo.all(from(n in Neuron, order_by: [asc: n.team, asc: n.name]))
  end

  defp neurons_for_cluster(neurons, cluster_name) do
    Enum.filter(neurons, fn n -> n.team == cluster_name end)
  end

  defp unclustered_neurons(neurons, clusters) do
    cluster_names = MapSet.new(clusters, & &1.cluster_name)
    Enum.filter(neurons, fn n -> is_nil(n.team) or not MapSet.member?(cluster_names, n.team) end)
  end

  defp status_color("active"), do: "green"
  defp status_color("shadow"), do: "cyan"
  defp status_color("paused"), do: "amber"
  defp status_color("archived"), do: "red"
  defp status_color(_), do: "dim"
end
