defmodule ExCortexWeb.RuminationsLive do
  @moduledoc "Pipeline builder and run history screen."
  use ExCortexWeb, :live_view

  alias ExCortex.Ruminations

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCortex.PubSub, "daydreams")
    end

    ruminations = Ruminations.list_ruminations()
    synapses = Ruminations.list_synapses()

    {:ok,
     assign(socket,
       page_title: "Ruminations",
       ruminations: ruminations,
       synapses: synapses,
       selected_id: nil,
       selected_rumination: nil,
       daydreams: [],
       running: %{},
       adhoc_input: "",
       output_dest: nil,
       editing: false,
       editing_rumination: nil,
       pipeline_steps: [],
       expanded_step: nil,
       synapse_picker: nil,
       synapse_search: "",
       picker_tab: "existing",
       new_synapse_name: "",
       focused_step: 0,
       rumination_form: %{}
     )}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    rumination_id = String.to_integer(id)
    {:noreply, load_rumination(socket, rumination_id)}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # PubSub — live run updates
  @impl true
  def handle_info({:daydream_started, run}, socket) do
    running = Map.put(socket.assigns.running, run.rumination_id, :running)

    daydreams =
      if socket.assigns.selected_id == run.rumination_id do
        [run | socket.assigns.daydreams]
      else
        socket.assigns.daydreams
      end

    {:noreply, assign(socket, running: running, daydreams: daydreams)}
  end

  def handle_info({:daydream_completed, run}, socket) do
    running = Map.delete(socket.assigns.running, run.rumination_id)

    daydreams =
      if socket.assigns.selected_id == run.rumination_id do
        Enum.map(socket.assigns.daydreams, fn d ->
          if d.id == run.id, do: run, else: d
        end)
      else
        socket.assigns.daydreams
      end

    rumination_name =
      case Enum.find(socket.assigns.ruminations, &(&1.id == run.rumination_id)) do
        %{name: name} -> name
        _ -> "Rumination ##{run.rumination_id}"
      end

    socket =
      socket
      |> assign(running: running, daydreams: daydreams)
      |> put_flash(:info, "#{rumination_name} completed (#{run.status})")

    {:noreply, socket}
  end

  # Internal task result (fallback for when PubSub doesn't fire)
  def handle_info({:run_complete, rumination_id, _result}, socket) do
    running = Map.delete(socket.assigns.running, rumination_id)

    daydreams =
      if socket.assigns.selected_id == rumination_id do
        rumination = Ruminations.get_rumination!(rumination_id)
        Ruminations.list_daydreams(rumination)
      else
        socket.assigns.daydreams
      end

    {:noreply, assign(socket, running: running, daydreams: daydreams)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Events

  @impl true
  def handle_event("select_rumination", %{"id" => id}, socket) do
    rumination_id = String.to_integer(id)
    {:noreply, load_rumination(socket, rumination_id)}
  end

  def handle_event("run_rumination", %{"id" => id}, socket) do
    rumination = Ruminations.get_rumination!(String.to_integer(id))
    input = socket.assigns.adhoc_input
    parent = self()

    Task.start(fn ->
      result = ExCortex.Ruminations.Runner.run(rumination, input)
      send(parent, {:run_complete, rumination.id, result})
    end)

    running = Map.put(socket.assigns.running, rumination.id, :running)
    {:noreply, assign(socket, running: running)}
  end

  def handle_event("delete_rumination", %{"id" => id}, socket) do
    rumination = Ruminations.get_rumination!(String.to_integer(id))
    Ruminations.delete_rumination(rumination)
    ruminations = Ruminations.list_ruminations()

    socket =
      if socket.assigns.selected_id == rumination.id do
        assign(socket, selected_id: nil, selected_rumination: nil, daydreams: [])
      else
        socket
      end

    {:noreply, assign(socket, ruminations: ruminations)}
  end

  def handle_event("navigate", %{"to" => path}, socket) do
    {:noreply, push_navigate(socket, to: path)}
  end

  def handle_event("set_adhoc_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, adhoc_input: value)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_id: nil, selected_rumination: nil, daydreams: [])}
  end

  def handle_event("new_rumination", _params, socket) do
    {:noreply,
     assign(socket,
       editing: true,
       editing_rumination: nil,
       pipeline_steps: [],
       expanded_step: nil,
       synapse_picker: nil,
       rumination_form: %{
         "name" => "",
         "description" => "",
         "trigger" => "manual",
         "schedule" => ""
       }
     )}
  end

  def handle_event("edit_rumination", _params, %{assigns: %{selected_rumination: rum}} = socket) when not is_nil(rum) do
    steps =
      rum.steps
      |> Enum.sort_by(&(&1["order"] || 0))
      |> Enum.with_index()
      |> Enum.map(fn {step, idx} ->
        synapse = Enum.find(socket.assigns.synapses, &(&1.id == step["step_id"]))

        %{
          "idx" => idx,
          "step_id" => step["step_id"],
          "synapse" => synapse,
          "gate" => Map.get(step, "gate", false),
          "type" => Map.get(step, "type", "linear"),
          "synthesizer" => Map.get(step, "synthesizer")
        }
      end)

    {:noreply,
     assign(socket,
       editing: true,
       editing_rumination: rum,
       pipeline_steps: steps,
       expanded_step: nil,
       synapse_picker: nil,
       rumination_form: %{
         "name" => rum.name,
         "description" => rum.description || "",
         "trigger" => rum.trigger,
         "schedule" => rum.schedule || ""
       }
     )}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     assign(socket,
       editing: false,
       editing_rumination: nil,
       pipeline_steps: [],
       expanded_step: nil,
       synapse_picker: nil,
       rumination_form: %{}
     )}
  end

  def handle_event("update_rumination_form", %{"field" => field, "value" => value}, socket) do
    form = Map.put(socket.assigns.rumination_form, field, value)
    {:noreply, assign(socket, rumination_form: form)}
  end

  def handle_event("expand_step", %{"idx" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    expanded = if socket.assigns.expanded_step == idx, do: nil, else: idx
    {:noreply, assign(socket, expanded_step: expanded)}
  end

  def handle_event("move_step_up", %{"idx" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    steps = socket.assigns.pipeline_steps

    if idx > 0 do
      {item, rest} = List.pop_at(steps, idx)

      steps =
        rest
        |> List.insert_at(idx - 1, item)
        |> Enum.with_index()
        |> Enum.map(fn {s, i} -> Map.put(s, "idx", i) end)

      {:noreply, assign(socket, pipeline_steps: steps, expanded_step: idx - 1)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("move_step_down", %{"idx" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    steps = socket.assigns.pipeline_steps

    if idx < length(steps) - 1 do
      {item, rest} = List.pop_at(steps, idx)

      steps =
        rest
        |> List.insert_at(idx, item)
        |> Enum.with_index()
        |> Enum.map(fn {s, i} -> Map.put(s, "idx", i) end)

      {:noreply, assign(socket, pipeline_steps: steps, expanded_step: idx + 1)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_step", %{"idx" => idx_str}, socket) do
    idx = String.to_integer(idx_str)

    steps =
      socket.assigns.pipeline_steps
      |> List.delete_at(idx)
      |> Enum.with_index()
      |> Enum.map(fn {s, i} -> Map.put(s, "idx", i) end)

    expanded = if socket.assigns.expanded_step == idx, do: nil, else: socket.assigns.expanded_step
    {:noreply, assign(socket, pipeline_steps: steps, expanded_step: expanded)}
  end

  def handle_event("toggle_step_option", %{"idx" => idx_str, "option" => option}, socket) do
    idx = String.to_integer(idx_str)
    steps = socket.assigns.pipeline_steps
    step = Enum.at(steps, idx)

    updated_step =
      case option do
        "gate" ->
          Map.update(step, "gate", true, &(!&1))

        "branch" ->
          Map.update(step, "type", "branch", fn
            "branch" -> "linear"
            _ -> "branch"
          end)

        _ ->
          step
      end

    steps = List.replace_at(steps, idx, updated_step)
    {:noreply, assign(socket, pipeline_steps: steps)}
  end

  def handle_event("add_roster_entry", %{"step-idx" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    steps = socket.assigns.pipeline_steps
    step = Enum.at(steps, idx)
    synapse = step["synapse"]

    if synapse do
      new_entry = %{"who" => "all", "when" => "sequential", "how" => "solo"}
      updated_roster = (synapse.roster || []) ++ [new_entry]
      updated_synapse = %{synapse | roster: updated_roster}
      updated_step = Map.put(step, "synapse", updated_synapse)
      steps = List.replace_at(steps, idx, updated_step)
      {:noreply, assign(socket, pipeline_steps: steps)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_roster_entry", %{"step-idx" => sidx, "roster-idx" => ridx}, socket) do
    sidx = String.to_integer(sidx)
    ridx = String.to_integer(ridx)
    steps = socket.assigns.pipeline_steps
    step = Enum.at(steps, sidx)
    synapse = step["synapse"]

    if synapse do
      updated_roster = List.delete_at(synapse.roster || [], ridx)
      updated_synapse = %{synapse | roster: updated_roster}
      updated_step = Map.put(step, "synapse", updated_synapse)
      steps = List.replace_at(steps, sidx, updated_step)
      {:noreply, assign(socket, pipeline_steps: steps)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "update_roster_entry",
        %{"step-idx" => sidx, "roster-idx" => ridx, "field" => field, "value" => value},
        socket
      ) do
    sidx = String.to_integer(sidx)
    ridx = String.to_integer(ridx)
    steps = socket.assigns.pipeline_steps
    step = Enum.at(steps, sidx)
    synapse = step["synapse"]

    if synapse do
      roster = synapse.roster || []
      entry = roster |> Enum.at(ridx) |> Map.put(field, value)
      updated_roster = List.replace_at(roster, ridx, entry)
      updated_synapse = %{synapse | roster: updated_roster}
      updated_step = Map.put(step, "synapse", updated_synapse)
      steps = List.replace_at(steps, sidx, updated_step)
      {:noreply, assign(socket, pipeline_steps: steps)}
    else
      {:noreply, socket}
    end
  end

  # Helpers

  defp load_rumination(socket, rumination_id) do
    rumination = Ruminations.get_rumination!(rumination_id)
    daydreams = Ruminations.list_daydreams(rumination)
    output_dest = last_step_output_destination(rumination, socket.assigns.synapses)

    assign(socket,
      selected_id: rumination_id,
      selected_rumination: rumination,
      daydreams: daydreams,
      output_dest: output_dest
    )
  end

  defp last_step_output_destination(rumination, synapses) do
    last_step_id =
      rumination.steps
      |> Enum.sort_by(&(&1["order"] || 0))
      |> List.last()
      |> case do
        %{"step_id" => id} -> id
        _ -> nil
      end

    synapse = Enum.find(synapses, &(&1.id == last_step_id))

    case synapse do
      %{output_type: "signal"} -> {:cortex, "→ signal on cortex"}
      %{output_type: "artifact"} -> {:memory, "→ engram in memory"}
      _ -> nil
    end
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
        <%!-- Left panel: rumination list --%>
        <div class="md:col-span-1">
          <.panel title="ruminations">
            <button
              phx-click="new_rumination"
              class="w-full text-left px-2 py-1.5 rounded text-sm t-cyan hover:bg-muted/40 transition-colors mb-2"
            >
              [+] new rumination
            </button>
            <%= if @ruminations == [] do %>
              <p class="text-xs t-dim py-2">
                No ruminations yet. Create one from the
                <a href="/ruminations" class="underline">Ruminations</a>
                page.
              </p>
            <% else %>
              <div class="space-y-1">
                <%= for rumination <- @ruminations do %>
                  <button
                    class={"w-full text-left px-2 py-1.5 rounded text-sm flex items-center gap-2 hover:bg-muted/40 transition-colors " <> if(@selected_id == rumination.id, do: "bg-muted/60 font-medium", else: "")}
                    phx-click="select_rumination"
                    phx-value-id={rumination.id}
                  >
                    <.status color={status_color(rumination.status)} label="" />
                    <span class="flex-1 truncate">{rumination.name}</span>
                    <%= if Map.get(@running, rumination.id) == :running do %>
                      <span class="text-xs t-amber animate-pulse">running</span>
                    <% else %>
                      <span class="text-xs t-dim">{step_count(rumination)}s</span>
                    <% end %>
                  </button>
                <% end %>
              </div>
            <% end %>
          </.panel>
        </div>

        <%!-- Right panel: builder or detail/empty state --%>
        <div class="md:col-span-2 space-y-4">
          <%= if @editing do %>
            <.panel title={
              if @editing_rumination, do: "edit: #{@rumination_form["name"]}", else: "new rumination"
            }>
              <div class="space-y-4">
                <%!-- Meta form --%>
                <div class="space-y-2">
                  <div>
                    <label class="text-xs t-dim uppercase tracking-wide">name</label>
                    <input
                      type="text"
                      value={@rumination_form["name"]}
                      phx-blur="update_rumination_form"
                      phx-value-field="name"
                      class="w-full h-8 text-sm border border-input rounded-md px-3 bg-background"
                    />
                  </div>
                  <div>
                    <label class="text-xs t-dim uppercase tracking-wide">description</label>
                    <input
                      type="text"
                      value={@rumination_form["description"]}
                      phx-blur="update_rumination_form"
                      phx-value-field="description"
                      class="w-full h-8 text-sm border border-input rounded-md px-3 bg-background"
                    />
                  </div>
                  <div class="flex gap-4">
                    <div class="flex-1">
                      <label class="text-xs t-dim uppercase tracking-wide">trigger</label>
                      <select
                        phx-change="update_rumination_form"
                        name="value"
                        phx-value-field="trigger"
                        class="w-full h-8 text-sm border border-input rounded-md px-2 bg-background"
                      >
                        <%= for t <- ~w(manual source scheduled once memory cortex) do %>
                          <option value={t} selected={@rumination_form["trigger"] == t}>{t}</option>
                        <% end %>
                      </select>
                    </div>
                    <%= if @rumination_form["trigger"] in ~w(scheduled once) do %>
                      <div class="flex-1">
                        <label class="text-xs t-dim uppercase tracking-wide">schedule</label>
                        <input
                          type="text"
                          value={@rumination_form["schedule"]}
                          phx-blur="update_rumination_form"
                          phx-value-field="schedule"
                          placeholder="*/30 * * * *"
                          class="w-full h-8 text-sm border border-input rounded-md px-3 bg-background"
                        />
                      </div>
                    <% end %>
                  </div>
                </div>

                <%!-- Step chain --%>
                <div class="border-t pt-3">
                  <p class="text-xs t-dim uppercase tracking-wide mb-2">synapse chain</p>
                  <.step_chain
                    steps={@pipeline_steps}
                    expanded={@expanded_step}
                    focused={@focused_step}
                    synapses={@synapses}
                  />
                </div>

                <%!-- Action bar --%>
                <div class="flex gap-2 border-t pt-3">
                  <.button size="sm" phx-click="save_rumination">save</.button>
                  <.button size="sm" variant="ghost" phx-click="cancel_edit">cancel</.button>
                  <%= if @editing_rumination do %>
                    <div class="flex-1" />
                    <.button
                      size="sm"
                      variant="ghost"
                      class="text-destructive"
                      phx-click="delete_rumination"
                      phx-value-id={@editing_rumination.id}
                      data-confirm={"Delete \"#{@editing_rumination.name}\"?"}
                    >
                      delete
                    </.button>
                  <% end %>
                </div>
              </div>
            </.panel>
          <% else %>
            <%= if @selected_rumination do %>
              <.panel title={@selected_rumination.name}>
                <div class="space-y-4">
                  <%!-- Meta row --%>
                  <div class="flex items-center gap-3 text-sm flex-wrap">
                    <.status
                      color={status_color(@selected_rumination.status)}
                      label={@selected_rumination.status}
                    />
                    <span class="t-dim">trigger: {@selected_rumination.trigger}</span>
                    <%= if @selected_rumination.schedule do %>
                      <span class="t-dim">schedule: {@selected_rumination.schedule}</span>
                    <% end %>
                    <span class="t-dim">
                      {step_count(@selected_rumination)} synapse{if step_count(@selected_rumination) !=
                                                                      1,
                                                                    do: "s"}
                    </span>
                  </div>

                  <%= if @selected_rumination.description do %>
                    <p class="text-sm text-muted-foreground">{@selected_rumination.description}</p>
                  <% end %>

                  <%!-- Synapse chain --%>
                  <%= if step_count(@selected_rumination) > 0 do %>
                    <div>
                      <p class="text-xs t-dim uppercase tracking-wide mb-2">Synapse Chain</p>
                      <div class="space-y-1">
                        <%= for {step, idx} <- Enum.with_index(@selected_rumination.steps) do %>
                          <div class="flex items-center gap-2 text-sm">
                            <span class="t-dim font-mono text-xs w-4 shrink-0">{idx + 1}.</span>
                            <span class="flex-1 truncate">
                              {synapse_name(
                                @synapses,
                                Map.get(step, "step_id") || Map.get(step, "id")
                              )}
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
                        aria-label="Ad-hoc run input"
                        phx-blur="set_adhoc_input"
                        phx-value-value={@adhoc_input}
                        class="flex-1 h-8 text-sm border border-input rounded-md px-3 bg-background"
                      />
                      <.button
                        size="sm"
                        phx-click="run_rumination"
                        phx-value-id={@selected_rumination.id}
                        disabled={Map.get(@running, @selected_rumination.id) == :running}
                      >
                        {if Map.get(@running, @selected_rumination.id) == :running,
                          do: "Running…",
                          else: "▶ Run"}
                      </.button>
                    </div>
                  </div>

                  <%!-- Actions --%>
                  <div class="flex gap-2 border-t pt-3">
                    <.button size="sm" variant="ghost" phx-click="edit_rumination">
                      Edit
                    </.button>
                    <.button
                      size="sm"
                      variant="ghost"
                      class="text-destructive hover:text-destructive"
                      phx-click="delete_rumination"
                      phx-value-id={@selected_rumination.id}
                      data-confirm={"Delete rumination \"#{@selected_rumination.name}\"?"}
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
                      <.daydream_row run={run} output_dest={@output_dest} />
                    <% end %>
                  </div>
                <% end %>
              </.panel>
            <% else %>
              <.panel title="select a rumination">
                <p class="text-sm t-dim py-4 text-center">
                  Choose a rumination from the list to view its synapse chain and run history.
                </p>
              </.panel>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :steps, :list, required: true
  attr :expanded, :any, default: nil
  attr :focused, :integer, default: 0
  attr :synapses, :list, required: true

  defp step_chain(assigns) do
    ~H"""
    <div class="font-mono text-sm">
      <%= if @steps == [] do %>
        <p class="text-xs t-dim italic py-2 pl-4">no steps — click [+] to add a synapse</p>
      <% else %>
        <%= for {step, idx} <- Enum.with_index(@steps) do %>
          <.step_card
            step={step}
            idx={idx}
            total={length(@steps)}
            expanded={@expanded == idx}
            focused={@focused == idx}
          />
          <%= if idx < length(@steps) - 1 do %>
            <div class="flex justify-center py-0.5">
              <span class="t-dim">│</span>
            </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :step, :map, required: true
  attr :idx, :integer, required: true
  attr :total, :integer, required: true
  attr :expanded, :boolean, default: false
  attr :focused, :boolean, default: false

  defp step_card(assigns) do
    synapse = assigns.step["synapse"]
    neuron_count = if synapse, do: length(synapse.roster || []), else: 0
    assigns = assign(assigns, synapse: synapse, neuron_count: neuron_count)

    ~H"""
    <div class={
      "border rounded px-3 py-2 " <>
        cond do
          @expanded -> "border-primary bg-muted/20"
          @focused -> "border-cyan"
          true -> "border-input"
        end
    }>
      <%!-- Compact header --%>
      <div class="flex items-center gap-2">
        <span class="t-dim font-mono text-xs w-4 shrink-0">{@idx + 1}.</span>
        <button class="flex-1 text-left truncate" phx-click="expand_step" phx-value-idx={@idx}>
          {if @synapse, do: @synapse.name, else: "unknown synapse"}
        </button>
        <span class="text-xs t-dim">◆ {@neuron_count}</span>
        <%= if @step["gate"] do %>
          <span class="text-xs t-red">▣ gate</span>
        <% end %>
        <%= if @step["type"] == "branch" do %>
          <span class="text-xs t-amber">⑂ branch</span>
        <% end %>
        <span class="flex gap-1">
          <button
            phx-click="move_step_up"
            phx-value-idx={@idx}
            disabled={@idx == 0}
            class={"text-xs px-1 " <> if(@idx == 0, do: "t-dim", else: "hover:bg-muted")}
            title="Move up"
          >
            ▲
          </button>
          <button
            phx-click="move_step_down"
            phx-value-idx={@idx}
            disabled={@idx == @total - 1}
            class={
              "text-xs px-1 " <> if(@idx == @total - 1, do: "t-dim", else: "hover:bg-muted")
            }
            title="Move down"
          >
            ▼
          </button>
          <button
            phx-click="remove_step"
            phx-value-idx={@idx}
            class="text-xs px-1 text-destructive hover:bg-muted"
            title="Remove"
          >
            −
          </button>
        </span>
      </div>
      <%!-- Expanded detail --%>
      <%= if @expanded do %>
        <div class="mt-3 pt-3 border-t border-dashed space-y-3">
          <%!-- Roster display --%>
          <div>
            <p class="text-xs t-dim uppercase tracking-wide mb-1">roster</p>
            <%= if @synapse && is_list(@synapse.roster) do %>
              <%= for {entry, ridx} <- Enum.with_index(@synapse.roster) do %>
                <div class="flex items-center gap-2 text-sm py-1">
                  <span class="text-xs t-dim w-8">who:</span>
                  <input
                    type="text"
                    value={Map.get(entry, "who", "")}
                    phx-blur="update_roster_entry"
                    phx-value-step-idx={@idx}
                    phx-value-roster-idx={ridx}
                    phx-value-field="who"
                    class="flex-1 h-7 text-xs border border-input rounded px-2 bg-background"
                    placeholder="all | master | team:Name | neuron_id"
                  />
                  <span class="text-xs t-dim w-10">when:</span>
                  <select
                    phx-change="update_roster_entry"
                    name="value"
                    phx-value-step-idx={@idx}
                    phx-value-roster-idx={ridx}
                    phx-value-field="when"
                    class="h-7 text-xs border border-input rounded px-1 bg-background"
                  >
                    <option value="sequential" selected={Map.get(entry, "when") == "sequential"}>
                      seq
                    </option>
                    <option value="parallel" selected={Map.get(entry, "when") == "parallel"}>
                      par
                    </option>
                  </select>
                  <span class="text-xs t-dim w-8">how:</span>
                  <select
                    phx-change="update_roster_entry"
                    name="value"
                    phx-value-step-idx={@idx}
                    phx-value-roster-idx={ridx}
                    phx-value-field="how"
                    class="h-7 text-xs border border-input rounded px-1 bg-background"
                  >
                    <%= for h <- ~w(solo consensus majority) do %>
                      <option value={h} selected={Map.get(entry, "how") == h}>{h}</option>
                    <% end %>
                  </select>
                  <button
                    phx-click="remove_roster_entry"
                    phx-value-step-idx={@idx}
                    phx-value-roster-idx={ridx}
                    class="text-xs text-destructive px-1"
                  >
                    −
                  </button>
                </div>
              <% end %>
            <% end %>
            <button
              phx-click="add_roster_entry"
              phx-value-step-idx={@idx}
              class="text-xs t-cyan hover:underline mt-1"
            >
              + add roster entry
            </button>
          </div>
          <%!-- Step options --%>
          <div class="flex gap-4 text-xs">
            <label class="flex items-center gap-1">
              <input
                type="checkbox"
                checked={@step["gate"]}
                phx-click="toggle_step_option"
                phx-value-idx={@idx}
                phx-value-option="gate"
              /> gate
            </label>
            <label class="flex items-center gap-1">
              <input
                type="checkbox"
                checked={@step["type"] == "branch"}
                phx-click="toggle_step_option"
                phx-value-idx={@idx}
                phx-value-option="branch"
              /> branch
            </label>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :run, :map, required: true
  attr :output_dest, :any, default: nil

  defp daydream_row(assigns) do
    ~H"""
    <div class="flex items-start gap-3 text-sm py-1.5 border-b last:border-0">
      <.status color={run_color(@run.status)} label={@run.status} />
      <span class="t-dim text-xs">{format_time(@run.inserted_at)}</span>
      <%= if @run.synapse_results != %{} do %>
        <span class="text-xs t-dim">
          {map_size(@run.synapse_results)} step{if map_size(@run.synapse_results) != 1, do: "s"}
        </span>
      <% end %>
      <%= if @run.status == "complete" && @output_dest do %>
        <.link
          navigate={output_dest_path(@output_dest)}
          class="text-xs t-cyan hover:underline ml-auto"
        >
          {elem(@output_dest, 1)}
        </.link>
      <% end %>
    </div>
    """
  end

  defp output_dest_path({:cortex, _}), do: ~p"/cortex"
  defp output_dest_path({:memory, _}), do: ~p"/memory"
  defp output_dest_path(_), do: ~p"/cortex"
end
