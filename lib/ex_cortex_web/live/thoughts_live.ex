defmodule ExCortexWeb.ThoughtsLive do
  @moduledoc "Pipeline builder and run history screen."
  use ExCortexWeb, :live_view

  alias ExCortex.Thoughts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCortex.PubSub, "daydreams")
    end

    thoughts = Thoughts.list_thoughts()
    synapses = Thoughts.list_synapses()

    {:ok,
     assign(socket,
       page_title: "Thoughts",
       thoughts: thoughts,
       synapses: synapses,
       selected_id: nil,
       selected_thought: nil,
       daydreams: [],
       running: %{},
       adhoc_input: ""
     )}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    thought_id = String.to_integer(id)
    {:noreply, load_thought(socket, thought_id)}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # PubSub — live run updates
  @impl true
  def handle_info({:daydream_started, run}, socket) do
    running = Map.put(socket.assigns.running, run.thought_id, :running)

    daydreams =
      if socket.assigns.selected_id == run.thought_id do
        [run | socket.assigns.daydreams]
      else
        socket.assigns.daydreams
      end

    {:noreply, assign(socket, running: running, daydreams: daydreams)}
  end

  def handle_info({:daydream_completed, run}, socket) do
    running = Map.delete(socket.assigns.running, run.thought_id)

    daydreams =
      if socket.assigns.selected_id == run.thought_id do
        Enum.map(socket.assigns.daydreams, fn d ->
          if d.id == run.id, do: run, else: d
        end)
      else
        socket.assigns.daydreams
      end

    {:noreply, assign(socket, running: running, daydreams: daydreams)}
  end

  # Internal task result (fallback for when PubSub doesn't fire)
  def handle_info({:run_complete, thought_id, _result}, socket) do
    running = Map.delete(socket.assigns.running, thought_id)

    daydreams =
      if socket.assigns.selected_id == thought_id do
        thought = Thoughts.get_thought!(thought_id)
        Thoughts.list_daydreams(thought)
      else
        socket.assigns.daydreams
      end

    {:noreply, assign(socket, running: running, daydreams: daydreams)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Events

  @impl true
  def handle_event("select_thought", %{"id" => id}, socket) do
    thought_id = String.to_integer(id)
    {:noreply, load_thought(socket, thought_id)}
  end

  def handle_event("run_thought", %{"id" => id}, socket) do
    thought = Thoughts.get_thought!(String.to_integer(id))
    input = socket.assigns.adhoc_input
    parent = self()

    Task.start(fn ->
      result = ExCortex.Thoughts.Runner.run(thought, input)
      send(parent, {:run_complete, thought.id, result})
    end)

    running = Map.put(socket.assigns.running, thought.id, :running)
    {:noreply, assign(socket, running: running)}
  end

  def handle_event("delete_thought", %{"id" => id}, socket) do
    thought = Thoughts.get_thought!(String.to_integer(id))
    Thoughts.delete_thought(thought)
    thoughts = Thoughts.list_thoughts()

    socket =
      if socket.assigns.selected_id == thought.id do
        assign(socket, selected_id: nil, selected_thought: nil, daydreams: [])
      else
        socket
      end

    {:noreply, assign(socket, thoughts: thoughts)}
  end

  def handle_event("navigate", %{"to" => path}, socket) do
    {:noreply, push_navigate(socket, to: path)}
  end

  def handle_event("set_adhoc_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, adhoc_input: value)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_id: nil, selected_thought: nil, daydreams: [])}
  end

  # Helpers

  defp load_thought(socket, thought_id) do
    thought = Thoughts.get_thought!(thought_id)
    daydreams = Thoughts.list_daydreams(thought)
    assign(socket, selected_id: thought_id, selected_thought: thought, daydreams: daydreams)
  end

  defp status_color("active"), do: "green"
  defp status_color("paused"), do: "amber"
  defp status_color("done"), do: "cyan"
  defp status_color(_), do: "dim"

  defp run_color("complete"), do: "green"
  defp run_color("failed"), do: "red"
  defp run_color("running"), do: "amber"
  defp run_color(_), do: "dim"

  defp format_time(nil), do: "never"

  defp format_time(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%b %d %H:%M")
  end

  defp format_time(%DateTime{} = dt) do
    dt |> DateTime.to_naive() |> format_time()
  end

  defp step_count(%{steps: steps}) when is_list(steps), do: length(steps)
  defp step_count(_), do: 0

  defp synapse_name(synapses, step_id) do
    id_str = to_string(step_id)

    case Enum.find(synapses, fn s -> to_string(s.id) == id_str end) do
      nil -> "synapse ##{step_id}"
      s -> s.name
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-3xl font-bold tracking-tight">Thoughts</h1>
          <p class="text-muted-foreground mt-1">
            Pipelines — define synapse chains, run on demand or by trigger.
          </p>
        </div>
        <.key_hints hints={[{"n", "new"}, {"r", "run"}, {"d", "delete"}, {"esc", "back"}]} />
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4 items-start">
        <%!-- Left panel: thought list --%>
        <div class="md:col-span-1">
          <.panel title="thoughts">
            <%= if @thoughts == [] do %>
              <p class="text-xs t-dim py-2">
                No thoughts yet. Create one from the
                <a href="/thoughts" class="underline">Thoughts</a>
                page.
              </p>
            <% else %>
              <div class="space-y-1">
                <%= for thought <- @thoughts do %>
                  <button
                    class={"w-full text-left px-2 py-1.5 rounded text-sm flex items-center gap-2 hover:bg-muted/40 transition-colors " <> if(@selected_id == thought.id, do: "bg-muted/60 font-medium", else: "")}
                    phx-click="select_thought"
                    phx-value-id={thought.id}
                  >
                    <.status color={status_color(thought.status)} label="" />
                    <span class="flex-1 truncate">{thought.name}</span>
                    <%= if Map.get(@running, thought.id) == :running do %>
                      <span class="text-xs t-amber animate-pulse">running</span>
                    <% else %>
                      <span class="text-xs t-dim">{step_count(thought)}s</span>
                    <% end %>
                  </button>
                <% end %>
              </div>
            <% end %>
          </.panel>
        </div>

        <%!-- Right panel: detail or empty state --%>
        <div class="md:col-span-2 space-y-4">
          <%= if @selected_thought do %>
            <.panel title={@selected_thought.name}>
              <div class="space-y-4">
                <%!-- Meta row --%>
                <div class="flex items-center gap-3 text-sm flex-wrap">
                  <.status
                    color={status_color(@selected_thought.status)}
                    label={@selected_thought.status}
                  />
                  <span class="t-dim">trigger: {@selected_thought.trigger}</span>
                  <%= if @selected_thought.schedule do %>
                    <span class="t-dim">schedule: {@selected_thought.schedule}</span>
                  <% end %>
                  <span class="t-dim">
                    {step_count(@selected_thought)} synapse{if step_count(@selected_thought) != 1,
                      do: "s"}
                  </span>
                </div>

                <%= if @selected_thought.description do %>
                  <p class="text-sm text-muted-foreground">{@selected_thought.description}</p>
                <% end %>

                <%!-- Synapse chain --%>
                <%= if step_count(@selected_thought) > 0 do %>
                  <div>
                    <p class="text-xs t-dim uppercase tracking-wide mb-2">Synapse Chain</p>
                    <div class="space-y-1">
                      <%= for {step, idx} <- Enum.with_index(@selected_thought.steps) do %>
                        <div class="flex items-center gap-2 text-sm">
                          <span class="t-dim font-mono text-xs w-4 shrink-0">{idx + 1}.</span>
                          <span class="flex-1 truncate">
                            {synapse_name(@synapses, Map.get(step, "step_id") || Map.get(step, "id"))}
                          </span>
                          <%= if Map.get(step, "type") == "branch" do %>
                            <span class="text-xs t-amber">branch</span>
                          <% end %>
                          <%= if Map.get(step, "gate") do %>
                            <span class="text-xs t-red">gate</span>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% else %>
                  <p class="text-xs t-dim italic">No synapses configured.</p>
                <% end %>

                <%!-- Ad-hoc runner --%>
                <div class="border-t pt-3 space-y-2">
                  <p class="text-xs t-dim uppercase tracking-wide">Ad-hoc Run</p>
                  <div class="flex gap-2">
                    <input
                      type="text"
                      value={@adhoc_input}
                      placeholder="Optional input text…"
                      phx-blur="set_adhoc_input"
                      phx-value-value={@adhoc_input}
                      class="flex-1 h-8 text-sm border border-input rounded-md px-3 bg-background"
                    />
                    <.button
                      size="sm"
                      phx-click="run_thought"
                      phx-value-id={@selected_thought.id}
                      disabled={Map.get(@running, @selected_thought.id) == :running}
                    >
                      {if Map.get(@running, @selected_thought.id) == :running,
                        do: "Running…",
                        else: "▶ Run"}
                    </.button>
                  </div>
                </div>

                <%!-- Actions --%>
                <div class="flex gap-2 border-t pt-3">
                  <.button
                    size="sm"
                    variant="ghost"
                    phx-click="navigate"
                    phx-value-to="/thoughts"
                  >
                    Edit
                  </.button>
                  <.button
                    size="sm"
                    variant="ghost"
                    class="text-destructive hover:text-destructive"
                    phx-click="delete_thought"
                    phx-value-id={@selected_thought.id}
                    data-confirm={"Delete thought \"#{@selected_thought.name}\"?"}
                  >
                    Delete
                  </.button>
                  <div class="flex-1" />
                  <.button size="sm" variant="ghost" phx-click="clear_selection">
                    ← Back
                  </.button>
                </div>
              </div>
            </.panel>

            <%!-- Run history --%>
            <.panel title="run history">
              <%= if @daydreams == [] do %>
                <p class="text-xs t-dim py-2">No runs yet.</p>
              <% else %>
                <div class="space-y-2">
                  <%= for run <- @daydreams do %>
                    <.daydream_row run={run} />
                  <% end %>
                </div>
              <% end %>
            </.panel>
          <% else %>
            <.panel title="select a thought">
              <p class="text-sm t-dim py-4 text-center">
                Choose a thought from the list to view its synapse chain and run history.
              </p>
            </.panel>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :run, :map, required: true

  defp daydream_row(assigns) do
    ~H"""
    <div class="flex items-start gap-3 text-sm py-1.5 border-b last:border-0">
      <.status color={run_color(@run.status)} label={@run.status} />
      <span class="t-dim text-xs">{format_time(@run.inserted_at)}</span>
      <%= if @run.synapse_results != %{} do %>
        <span class="text-xs t-dim ml-auto">
          {map_size(@run.synapse_results)} step{if map_size(@run.synapse_results) != 1, do: "s"}
        </span>
      <% end %>
    </div>
    """
  end
end
