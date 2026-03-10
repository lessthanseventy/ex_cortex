defmodule ExCaliburWeb.QuestsLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge

  alias ExCalibur.Board
  alias ExCalibur.Quests
  alias ExCalibur.Sources.Book
  alias ExCalibur.Sources.Source

  @impl true
  def mount(_params, _session, socket) do
    import Ecto.Query

    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCalibur.PubSub, "step_runs")
    end

    steps = Quests.list_steps()
    quests = Quests.list_quests()

    sources = ExCalibur.Repo.all(from(s in Source, order_by: [asc: s.inserted_at]))

    trigger_previews =
      quests
      |> Map.new(fn c -> {"quest-#{c.id}", c.trigger} end)
      |> Map.put("new-quest", "manual")

    schedule_mode_previews = build_schedule_mode_previews(quests)

    board_templates = Enum.map(Board.all(), &board_with_status/1)

    {:ok,
     assign(socket,
       steps: steps,
       quests: quests,
       sources: sources,
       expanded: MapSet.new(),
       running: %{},
       quest_runs: %{},
       trigger_previews: trigger_previews,
       schedule_mode_previews: schedule_mode_previews,
       board_templates: board_templates,
       board_show_unavailable: false,
       board_installing: nil,
       board_installed: MapSet.new(),
       board_tab: "all",
       quest_prefill: %{name: "", description: ""}
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Quests")}
  end

  @impl true
  def handle_event("board_toggle_unavailable", _params, socket) do
    {:noreply, assign(socket, board_show_unavailable: !socket.assigns.board_show_unavailable)}
  end

  @impl true
  def handle_event("board_confirm_install", %{"id" => id}, socket) do
    {:noreply, assign(socket, board_installing: id)}
  end

  @impl true
  def handle_event("board_cancel_install", _params, socket) do
    {:noreply, assign(socket, board_installing: nil)}
  end

  @impl true
  def handle_event("board_install_template", %{"id" => id}, socket) do
    case Board.get(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Template not found")}

      template ->
        case Board.install(template) do
          {:ok, _quest} ->
            installed = MapSet.put(socket.assigns.board_installed, id)

            {:noreply,
             socket
             |> assign(
               board_installed: installed,
               board_installing: nil,
               steps: Quests.list_steps(),
               quests: Quests.list_quests()
             )
             |> put_flash(:info, "\"#{template.name}\" installed!")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Install failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("toggle_expand", %{"id" => "quest-" <> quest_id_str = id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded, id),
        do: MapSet.delete(socket.assigns.expanded, id),
        else: MapSet.put(socket.assigns.expanded, id)

    quest_runs =
      if MapSet.member?(socket.assigns.expanded, id) do
        socket.assigns.quest_runs
      else
        quest = Quests.get_quest!(String.to_integer(quest_id_str))
        Map.put(socket.assigns.quest_runs, quest_id_str, Quests.list_quest_runs(quest))
      end

    {:noreply, assign(socket, expanded: expanded, quest_runs: quest_runs)}
  end

  def handle_event("toggle_expand", %{"id" => id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded, id),
        do: MapSet.delete(socket.assigns.expanded, id),
        else: MapSet.put(socket.assigns.expanded, id)

    {:noreply, assign(socket, expanded: expanded)}
  end

  @impl true
  def handle_event("board_set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, board_tab: tab)}
  end

  @impl true
  def handle_event("board_customize_template", %{"id" => id}, socket) do
    case Board.get(id) do
      nil ->
        {:noreply, socket}

      template ->
        prefill = %{
          name: template.name,
          description: template.description
        }

        {:noreply, assign(socket, board_tab: "custom", quest_prefill: prefill)}
    end
  end

  @impl true
  def handle_event("preview_quest_trigger", %{"quest_id" => id, "quest" => %{"trigger" => t}}, socket) do
    {:noreply, assign(socket, trigger_previews: Map.put(socket.assigns.trigger_previews, "quest-#{id}", t))}
  end

  def handle_event("preview_quest_trigger", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("preview_new_quest_trigger", %{"quest" => %{"trigger" => t}}, socket) do
    {:noreply, assign(socket, trigger_previews: Map.put(socket.assigns.trigger_previews, "new-quest", t))}
  end

  def handle_event("preview_new_quest_trigger", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_schedule_mode", %{"mode" => mode, "id" => form_id}, socket) do
    {:noreply, assign(socket, schedule_mode_previews: Map.put(socket.assigns.schedule_mode_previews, form_id, mode))}
  end

  @impl true
  def handle_event("move_quest_step_up", %{"quest_id" => id, "index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    quest = Quests.get_quest!(String.to_integer(id))
    steps = quest.steps
    {a, b} = {Enum.at(steps, idx - 1), Enum.at(steps, idx)}
    new_steps = steps |> List.replace_at(idx - 1, b) |> List.replace_at(idx, a)
    Quests.update_quest(quest, %{steps: new_steps})
    {:noreply, assign_quests(socket)}
  end

  @impl true
  def handle_event("move_quest_step_down", %{"quest_id" => id, "index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    quest = Quests.get_quest!(String.to_integer(id))
    steps = quest.steps
    {a, b} = {Enum.at(steps, idx), Enum.at(steps, idx + 1)}
    new_steps = steps |> List.replace_at(idx, b) |> List.replace_at(idx + 1, a)
    Quests.update_quest(quest, %{steps: new_steps})
    {:noreply, assign_quests(socket)}
  end

  @impl true
  def handle_event("remove_quest_step", %{"quest_id" => id, "index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    quest = Quests.get_quest!(String.to_integer(id))
    new_steps = List.delete_at(quest.steps, idx)
    Quests.update_quest(quest, %{steps: new_steps})
    {:noreply, assign_quests(socket)}
  end

  @impl true
  def handle_event("add_quest_step", %{"quest_id" => _id, "step_id" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("add_quest_step", %{"quest_id" => id, "step_id" => step_id}, socket) do
    quest = Quests.get_quest!(String.to_integer(id))
    new_step = %{"step_id" => step_id, "flow" => "always"}
    Quests.update_quest(quest, %{steps: quest.steps ++ [new_step]})
    {:noreply, assign_quests(socket)}
  end

  @impl true
  def handle_event("create_quest", %{"quest" => params}, socket) do
    step_ids = params |> Map.get("step_ids", []) |> List.wrap()
    steps = Enum.map(step_ids, &%{"step_id" => &1, "flow" => "always"})
    trigger = params["trigger"] || "manual"

    schedule =
      if trigger == "scheduled" do
        build_schedule_from_params(params)
      end

    run_at =
      if trigger == "once" && params["run_at"] && params["run_at"] != "" do
        naive = NaiveDateTime.from_iso8601!(params["run_at"] <> ":00")
        DateTime.from_naive!(naive, "Etc/UTC")
      end

    source_ids = if trigger == "source", do: params |> Map.get("source_ids", []) |> List.wrap(), else: []

    lore_trigger_tags =
      (params["lore_trigger_tags"] || "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    attrs = %{
      name: params["name"],
      description: params["description"],
      trigger: trigger,
      schedule: schedule,
      run_at: run_at,
      source_ids: source_ids,
      lore_trigger_tags: lore_trigger_tags,
      steps: steps,
      status: "active"
    }

    case Quests.create_quest(attrs) do
      {:ok, _} ->
        quests = Quests.list_quests()
        previews = rebuild_trigger_previews(socket.assigns.steps, quests, socket.assigns.trigger_previews)
        schedule_mode_previews = build_schedule_mode_previews(quests)

        {:noreply,
         assign(socket,
           quests: quests,
           board_tab: "all",
           quest_prefill: %{name: "", description: ""},
           trigger_previews: previews,
           schedule_mode_previews: schedule_mode_previews
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create quest")}
    end
  end

  @impl true
  def handle_event("update_quest", %{"quest" => params, "quest_id" => id}, socket) do
    quest = Quests.get_quest!(String.to_integer(id))
    trigger = params["trigger"] || "manual"

    schedule =
      if trigger == "scheduled" do
        build_schedule_from_params(params)
      end

    run_at =
      if trigger == "once" && params["run_at"] && params["run_at"] != "" do
        naive = NaiveDateTime.from_iso8601!(params["run_at"] <> ":00")
        DateTime.from_naive!(naive, "Etc/UTC")
      end

    source_ids = if trigger == "source", do: params |> Map.get("source_ids", []) |> List.wrap(), else: []

    lore_trigger_tags =
      (params["lore_trigger_tags"] || "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    attrs = %{
      name: params["name"],
      description: params["description"],
      trigger: trigger,
      schedule: schedule,
      run_at: run_at,
      source_ids: source_ids,
      lore_trigger_tags: lore_trigger_tags
    }

    case Quests.update_quest(quest, attrs) do
      {:ok, _} ->
        quests = Quests.list_quests()
        previews = rebuild_trigger_previews(socket.assigns.steps, quests, socket.assigns.trigger_previews)
        schedule_mode_previews = build_schedule_mode_previews(quests)

        {:noreply,
         assign(socket, quests: quests, trigger_previews: previews, schedule_mode_previews: schedule_mode_previews)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update quest")}
    end
  end

  @impl true
  def handle_event("toggle_quest_status", %{"id" => id}, socket) do
    quest = Quests.get_quest!(String.to_integer(id))
    new_status = if quest.status == "active", do: "paused", else: "active"
    Quests.update_quest(quest, %{status: new_status})
    {:noreply, assign_quests(socket)}
  end

  @impl true
  def handle_event("delete_quest", %{"id" => id}, socket) do
    quest = Quests.get_quest!(String.to_integer(id))
    Quests.delete_quest(quest)
    {:noreply, assign_quests(socket)}
  end

  @impl true
  def handle_event("run_quest_now", %{"id" => id}, socket) do
    quest = Quests.get_quest!(String.to_integer(id))
    run_id = "quest-#{quest.id}"

    {:ok, quest_run} = Quests.create_quest_run(%{quest_id: quest.id, status: "running"})

    running = Map.put(socket.assigns.running, run_id, %{status: "running", result: nil})
    parent = self()

    Task.start(fn ->
      result = ExCalibur.QuestRunner.run(quest, "")
      send(parent, {:quest_run_complete, run_id, quest_run.id, result})
    end)

    {:noreply, assign(socket, running: running)}
  end

  @impl true
  def handle_event("update_step_grimoire", %{"step_id" => step_id, "tags" => tags_str}, socket) do
    step = Quests.get_step!(String.to_integer(step_id))
    tags = tags_str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    new_providers =
      case tags do
        [] ->
          Enum.reject(step.context_providers, &(&1["type"] == "lore"))

        tags ->
          existing = Enum.reject(step.context_providers, &(&1["type"] == "lore"))
          existing ++ [%{"type" => "lore", "tags" => tags, "limit" => 10, "sort" => "top"}]
      end

    Quests.update_step(step, %{context_providers: new_providers})
    {:noreply, assign_steps(socket)}
  end

  def handle_event("update_step_lore_tags", %{"step_id" => step_id, "lore_tags" => tags_str}, socket) do
    step = Quests.get_step!(String.to_integer(step_id))
    tags = tags_str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    Quests.update_step(step, %{lore_tags: tags})
    {:noreply, assign_steps(socket)}
  end

  @impl true
  def handle_info({:quest_run_complete, run_id, quest_run_id, result}, socket) do
    {status, results} =
      case result do
        {:ok, outcome} -> {"complete", outcome}
        {:error, reason} -> {"failed", %{error: inspect(reason)}}
      end

    quest_run = ExCalibur.Repo.get!(ExCalibur.Quests.QuestRun, quest_run_id)
    Quests.update_quest_run(quest_run, %{status: status, step_results: results})

    running = Map.put(socket.assigns.running, run_id, %{status: status, result: results})
    {:noreply, assign(socket, running: running)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, quests: Quests.list_quests(), steps: Quests.list_steps())}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-10">
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Quests</h1>
        <p class="text-muted-foreground mt-1.5">
          Structured workflows — build steps, set a trigger, run on demand or on schedule.
        </p>
      </div>

      <%!-- Quests --%>
      <div>
        <div class="space-y-3">
          <.quest_card_comp
            :for={quest <- @quests}
            quest={quest}
            steps={@steps}
            sources={@sources}
            expanded={MapSet.member?(@expanded, "quest-#{quest.id}")}
            trigger_preview={@trigger_previews["quest-#{quest.id}"] || quest.trigger}
            schedule_mode_previews={@schedule_mode_previews}
            run_state={@running["quest-#{quest.id}"]}
            runs={@quest_runs[to_string(quest.id)] || []}
          />
          <%= if @quests == [] do %>
            <div class="text-center py-12 text-muted-foreground">
              <p class="text-sm">
                No quests yet. Create one in Quest Templates → Custom below.
              </p>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Quest Templates --%>
      <div>
        <div class="mb-4">
          <h2 class="text-lg font-semibold">Quest Templates</h2>
          <p class="text-sm text-muted-foreground">
            Pre-built quests ready to install. Each adds a workflow to your guild.
          </p>
        </div>

        <div class="flex overflow-x-auto border-b mb-6">
          <%= for {tab_id, label} <- [
            {"all", "All"},
            {"triage", "Triage"},
            {"reporting", "Reporting"},
            {"generation", "Generation"},
            {"review", "Review"},
            {"onboarding", "Onboarding"},
            {"lifestyle", "Lifestyle"},
            {"custom", "Custom"}
          ] do %>
            <button
              phx-click="board_set_tab"
              phx-value-tab={tab_id}
              class={[
                "px-4 py-2 text-sm whitespace-nowrap border-b-2 -mb-px transition-colors",
                if(@board_tab == tab_id,
                  do: "border-foreground text-foreground font-medium",
                  else: "border-transparent text-muted-foreground hover:text-foreground"
                )
              ]}
            >
              {label}
            </button>
          <% end %>
          <div class="ml-auto flex items-center pr-2">
            <button
              phx-click="board_toggle_unavailable"
              class="text-sm text-muted-foreground hover:text-foreground transition-colors whitespace-nowrap"
            >
              {if @board_show_unavailable, do: "Hide unavailable", else: "Show all"}
            </button>
          </div>
        </div>

        <%= if @board_tab == "custom" do %>
          <.new_quest_form_comp
            steps={@steps}
            sources={@sources}
            trigger_preview={@trigger_previews["new-quest"] || "manual"}
            prefill={@quest_prefill}
            schedule_mode_previews={@schedule_mode_previews}
          />
        <% else %>
          <div class="space-y-3">
            <%= for %{template: t, requirements: reqs, readiness: r} <- board_visible(@board_templates, board_tab_category(@board_tab), @board_show_unavailable) do %>
              <div class={[
                "flex flex-col gap-4 rounded-lg border p-5 sm:flex-row sm:items-start sm:justify-between",
                MapSet.member?(@board_installed, t.id) && "border-primary bg-accent/50",
                r == :unavailable && "opacity-60"
              ]}>
                <div class="space-y-2 flex-1 min-w-0">
                  <div class="flex items-center gap-2 flex-wrap">
                    <span class="font-semibold">{t.name}</span>
                    <.badge variant="outline" class="text-xs capitalize">
                      {board_category_label(t.category)}
                    </.badge>
                    <%= if MapSet.member?(@board_installed, t.id) do %>
                      <.badge variant="default">Installed</.badge>
                    <% else %>
                      <% {label, variant} = board_readiness_badge(r) %>
                      <.badge variant={variant}>{label}</.badge>
                    <% end %>
                  </div>
                  <p class="text-sm text-muted-foreground">{t.description}</p>
                  <%= if t.suggested_team && t.suggested_team != "" do %>
                    <p class="text-xs text-muted-foreground italic">Team: {t.suggested_team}</p>
                  <% end %>
                  <%= if length(reqs) > 0 do %>
                    <div class="flex flex-wrap gap-1.5 mt-1">
                      <%= for {met, req_label} <- reqs do %>
                        <.badge
                          variant={if met, do: "secondary", else: "outline"}
                          class="text-xs gap-1"
                        >
                          {if met, do: "✓", else: "○"} {req_label}
                        </.badge>
                      <% end %>
                    </div>
                  <% end %>
                </div>
                <div class="ml-4 shrink-0 self-center">
                  <%= if MapSet.member?(@board_installed, t.id) do %>
                    <.button variant="outline" size="sm" disabled>Installed</.button>
                  <% else %>
                    <%= if @board_installing == t.id do %>
                      <div class="flex gap-2">
                        <.button
                          variant="destructive"
                          size="sm"
                          phx-click="board_install_template"
                          phx-value-id={t.id}
                        >
                          Confirm
                        </.button>
                        <.button variant="outline" size="sm" phx-click="board_cancel_install">
                          Cancel
                        </.button>
                      </div>
                    <% else %>
                      <div class="flex gap-2">
                        <.button
                          variant={if r == :ready, do: "default", else: "outline"}
                          size="sm"
                          phx-click="board_confirm_install"
                          phx-value-id={t.id}
                          disabled={r == :unavailable}
                        >
                          Install
                        </.button>
                        <.button
                          variant="ghost"
                          size="sm"
                          phx-click="board_customize_template"
                          phx-value-id={t.id}
                        >
                          Customize
                        </.button>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>
            <% end %>
            <%= if board_visible(@board_templates, board_tab_category(@board_tab), @board_show_unavailable) == [] do %>
              <p class="text-sm text-muted-foreground py-6 text-center">
                No templates in this category.
                <button phx-click="board_toggle_unavailable" class="underline ml-1">Show all</button>
              </p>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :id_prefix, :string, required: true
  attr :namespace, :string, default: "quest"
  attr :mode, :string, default: "interval"
  attr :schedule, :string, default: ""

  defp schedule_picker(assigns) do
    info = parse_schedule_info(assigns.schedule)
    assigns = assign(assigns, :info, info)

    ~H"""
    <div class="space-y-2">
      <input type="hidden" name={@namespace <> "[schedule_mode]"} value={@mode} />
      <div class="flex items-center gap-2">
        <span class="text-sm text-muted-foreground shrink-0">Mode:</span>
        <select
          id={"schedule-mode-#{@id_prefix}"}
          class="h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
          phx-change="update_schedule_mode"
          phx-value-id={@id_prefix}
          name={"_schedule_mode_ui_#{@id_prefix}"}
        >
          <option value="interval" selected={@mode == "interval"}>Every interval</option>
          <option value="daily" selected={@mode == "daily"}>Daily at time</option>
          <option value="weekdays" selected={@mode == "weekdays"}>Weekdays at time</option>
          <option value="weekly" selected={@mode == "weekly"}>Weekly on day</option>
          <option value="monthly" selected={@mode == "monthly"}>Monthly on day</option>
        </select>
      </div>
      <%= if @mode == "interval" do %>
        <div class="flex items-center gap-2">
          <span class="text-sm text-muted-foreground shrink-0">Every</span>
          <input
            type="number"
            name={@namespace <> "[schedule_interval]"}
            value={@info.interval}
            min="1"
            class="w-20 h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
          />
          <select
            id={"schedule-unit-#{@id_prefix}"}
            name={@namespace <> "[schedule_unit]"}
            class="h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
          >
            <option value="minutes" selected={@info.unit == "minutes"}>minutes</option>
            <option value="hours" selected={@info.unit == "hours"}>hours</option>
          </select>
        </div>
      <% end %>
      <%= if @mode in ["daily", "weekdays"] do %>
        <div class="flex items-center gap-2">
          <span class="text-sm text-muted-foreground shrink-0">
            {if @mode == "daily", do: "Daily at", else: "Weekdays (Mon–Fri) at"}
          </span>
          <.time_selects
            namespace={@namespace}
            id_prefix={@id_prefix}
            hour={@info.hour}
            minute={@info.minute}
          />
        </div>
      <% end %>
      <%= if @mode == "weekly" do %>
        <div class="flex items-center gap-2">
          <span class="text-sm text-muted-foreground shrink-0">Every</span>
          <select
            name={@namespace <> "[schedule_day]"}
            class="h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
          >
            <option value="0" selected={@info.day == "0"}>Sun</option>
            <option value="1" selected={@info.day == "1"}>Mon</option>
            <option value="2" selected={@info.day == "2"}>Tue</option>
            <option value="3" selected={@info.day == "3"}>Wed</option>
            <option value="4" selected={@info.day == "4"}>Thu</option>
            <option value="5" selected={@info.day == "5"}>Fri</option>
            <option value="6" selected={@info.day == "6"}>Sat</option>
          </select>
          <span class="text-sm text-muted-foreground shrink-0">at</span>
          <.time_selects
            namespace={@namespace}
            id_prefix={@id_prefix}
            hour={@info.hour}
            minute={@info.minute}
          />
        </div>
      <% end %>
      <%= if @mode == "monthly" do %>
        <div class="flex items-center gap-2">
          <span class="text-sm text-muted-foreground shrink-0">On day</span>
          <input
            type="number"
            name={@namespace <> "[schedule_day]"}
            value={@info.day}
            min="1"
            max="28"
            class="w-20 h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
          />
          <span class="text-sm text-muted-foreground shrink-0">of every month at</span>
          <.time_selects
            namespace={@namespace}
            id_prefix={@id_prefix}
            hour={@info.hour}
            minute={@info.minute}
          />
        </div>
      <% end %>
    </div>
    """
  end

  attr :namespace, :string, required: true
  attr :id_prefix, :string, required: true
  attr :hour, :integer, default: 8
  attr :minute, :integer, default: 0

  defp time_selects(assigns) do
    ~H"""
    <select
      id={"schedule-hour-#{@id_prefix}"}
      name={@namespace <> "[schedule_hour]"}
      class="h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
    >
      <%= for h <- 0..23 do %>
        <option value={h} selected={@hour == h}>{hour_label(h)}</option>
      <% end %>
    </select>
    <select
      id={"schedule-minute-#{@id_prefix}"}
      name={@namespace <> "[schedule_minute]"}
      class="h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
    >
      <option value="0" selected={@minute == 0}>:00</option>
      <option value="15" selected={@minute == 15}>:15</option>
      <option value="30" selected={@minute == 30}>:30</option>
      <option value="45" selected={@minute == 45}>:45</option>
    </select>
    """
  end

  attr :sources, :list, default: []
  attr :namespace, :string, default: "quest"
  attr :selected_ids, :list, default: []

  defp source_picker(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <p class="text-sm font-medium">Library Sources</p>
      <%= if @sources == [] do %>
        <p class="text-xs text-muted-foreground">
          No active library sources. <a href="/library" class="underline">Add sources in Library.</a>
        </p>
      <% else %>
        <div class="rounded-md border border-input divide-y divide-border">
          <%= for source <- @sources do %>
            <% checked = source.id in @selected_ids %>
            <label class={[
              "flex items-center gap-3 px-3 py-2.5 cursor-pointer transition-colors",
              if(checked, do: "bg-primary/5", else: "hover:bg-muted/50")
            ]}>
              <input
                type="checkbox"
                name={@namespace <> "[source_ids][]"}
                value={source.id}
                checked={checked}
                class="h-4 w-4 shrink-0 rounded-sm border border-primary shadow focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring checked:bg-primary checked:text-primary-foreground"
              />
              <span class="flex-1 text-sm">{source_label(source)}</span>
              <.badge variant="outline" class="text-xs shrink-0">{source.source_type}</.badge>
            </label>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :steps, :list, required: true
  attr :sources, :list, default: []
  attr :trigger_preview, :string, default: "manual"
  attr :prefill, :map, default: %{name: "", description: ""}
  attr :schedule_mode_previews, :map, default: %{}

  defp new_quest_form_comp(assigns) do
    ~H"""
    <div class="border rounded-lg border-dashed p-4">
      <form phx-submit="create_quest" phx-change="preview_new_quest_trigger" class="space-y-3">
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <label class="text-sm font-medium">Name</label>
            <.input
              type="text"
              name="quest[name]"
              value={@prefill[:name]}
              placeholder="e.g. Monthly Audit"
            />
          </div>
          <div>
            <label class="text-sm font-medium">Description</label>
            <.input
              type="text"
              name="quest[description]"
              value={@prefill[:description]}
              placeholder="Optional"
            />
          </div>
        </div>
        <div>
          <label for="quest-trigger-new" class="text-sm font-medium">Trigger</label>
          <select
            id="quest-trigger-new"
            name="quest[trigger]"
            class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
          >
            <option value="manual">Manual</option>
            <option value="source">Library Source</option>
            <option value="scheduled">Scheduled</option>
            <option value="once">Once (specific time)</option>
            <option value="lore">Grimoire</option>
          </select>
        </div>
        <%= if @trigger_preview == "scheduled" do %>
          <.schedule_picker
            namespace="quest"
            id_prefix="new-quest"
            mode={Map.get(@schedule_mode_previews, "new-quest", "interval")}
            schedule=""
          />
        <% end %>
        <%= if @trigger_preview == "once" do %>
          <div>
            <label class="text-sm font-medium">Run at</label>
            <input
              type="datetime-local"
              name="quest[run_at]"
              class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background"
            />
          </div>
        <% end %>
        <%= if @trigger_preview == "source" do %>
          <.source_picker sources={@sources} namespace="quest" selected_ids={[]} />
        <% end %>
        <%= if @trigger_preview == "lore" do %>
          <div>
            <label class="text-sm font-medium">Trigger on tags</label>
            <input
              type="text"
              name="quest[lore_trigger_tags]"
              value=""
              placeholder="journal, decisions… (empty = all entries)"
              class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
            />
            <p class="text-xs text-muted-foreground mt-1">
              Fires when a Grimoire entry with matching tags is created.
            </p>
          </div>
        <% end %>
        <div>
          <label class="text-sm font-medium">Steps (select in order)</label>
          <select
            name="quest[step_ids][]"
            multiple
            class="w-full text-sm border rounded px-2 py-1 bg-background h-24"
          >
            <%= for quest <- @steps do %>
              <option value={quest.id}>{quest.name}</option>
            <% end %>
          </select>
          <p class="text-xs text-muted-foreground mt-1">Hold Ctrl/Cmd to select multiple</p>
        </div>
        <div class="flex justify-end gap-2">
          <.button
            type="button"
            variant="outline"
            size="sm"
            phx-click="board_set_tab"
            phx-value-tab="all"
          >
            Cancel
          </.button>
          <.button type="submit" size="sm">Create Quest</.button>
        </div>
      </form>
    </div>
    """
  end

  attr :quest, :map, required: true
  attr :steps, :list, required: true
  attr :sources, :list, default: []
  attr :expanded, :boolean, required: true
  attr :trigger_preview, :string, required: true
  attr :schedule_mode_previews, :map, default: %{}
  attr :run_state, :map, default: nil
  attr :runs, :list, default: []

  defp quest_card_comp(assigns) do
    ~H"""
    <div class={["border rounded-lg bg-card", if(@quest.status == "paused", do: "opacity-60")]}>
      <div class="flex items-stretch gap-3 px-5">
        <div
          class="flex flex-1 items-center gap-3 py-4 cursor-pointer min-w-0"
          phx-click="toggle_expand"
          phx-value-id={"quest-#{@quest.id}"}
        >
          <span class={[
            "transition-transform text-muted-foreground shrink-0",
            if(@expanded, do: "rotate-90")
          ]}>
            ›
          </span>
          <div class="flex-1 min-w-0">
            <span class="font-medium">{@quest.name}</span>
            <span class="text-xs text-muted-foreground ml-2">
              {length(@quest.steps)} steps
            </span>
            <%= if @quest.trigger == "lore" && @quest.lore_trigger_tags != [] do %>
              <span class="text-xs text-muted-foreground ml-1">
                · listening for:
                <span class="font-mono">{Enum.join(@quest.lore_trigger_tags, ", ")}</span>
              </span>
            <% end %>
            <%= if @quest.trigger == "lore" && (@quest.lore_trigger_tags == nil || @quest.lore_trigger_tags == []) do %>
              <span class="text-xs text-muted-foreground ml-1">
                · listening for all Grimoire entries
              </span>
            <% end %>
          </div>
          <.badge variant="outline" class="text-xs shrink-0">{trigger_label(@quest.trigger)}</.badge>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <.button
            size="sm"
            variant="outline"
            phx-click="run_quest_now"
            phx-value-id={@quest.id}
            disabled={@run_state && @run_state.status == "running"}
          >
            {if @run_state && @run_state.status == "running", do: "Running…", else: "▶ Run Now"}
          </.button>
          <.button
            size="sm"
            variant="ghost"
            phx-click="toggle_quest_status"
            phx-value-id={@quest.id}
          >
            {if @quest.status == "active", do: "Pause", else: "Resume"}
          </.button>
          <.button
            size="sm"
            variant="ghost"
            phx-click="delete_quest"
            phx-value-id={@quest.id}
            data-confirm="Delete this quest?"
          >
            Delete
          </.button>
        </div>
      </div>
      <%= if @expanded do %>
        <div class="border-t px-5 py-5">
          <form phx-submit="update_quest" phx-change="preview_quest_trigger" class="space-y-4">
            <input type="hidden" name="quest_id" value={@quest.id} />
            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div class="space-y-1.5">
                <label for={"qname-form-#{@quest.id}"} class="text-sm font-medium">Name</label>
                <.input
                  id={"qname-form-#{@quest.id}"}
                  type="text"
                  name="quest[name]"
                  value={@quest.name}
                />
              </div>
              <div class="space-y-1.5">
                <label for={"qdesc-form-#{@quest.id}"} class="text-sm font-medium">Description</label>
                <.input
                  id={"qdesc-form-#{@quest.id}"}
                  type="text"
                  name="quest[description]"
                  value={@quest.description || ""}
                  placeholder="Optional"
                />
              </div>
            </div>
            <div class="space-y-1.5">
              <label for={"qtrigger-form-#{@quest.id}"} class="text-sm font-medium">Trigger</label>
              <select
                id={"qtrigger-form-#{@quest.id}"}
                name="quest[trigger]"
                class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
              >
                <option value="manual" selected={@quest.trigger == "manual"}>Manual</option>
                <option value="source" selected={@quest.trigger == "source"}>Library Source</option>
                <option value="scheduled" selected={@quest.trigger == "scheduled"}>
                  Scheduled
                </option>
                <option value="once" selected={@quest.trigger == "once"}>
                  Once (specific time)
                </option>
                <option value="lore" selected={@quest.trigger == "lore"}>
                  Grimoire
                </option>
              </select>
            </div>
            <%= if @trigger_preview == "scheduled" do %>
              <.schedule_picker
                namespace="quest"
                id_prefix={"quest-#{@quest.id}"}
                mode={
                  Map.get(
                    @schedule_mode_previews,
                    "quest-#{@quest.id}",
                    detect_schedule_mode(@quest.schedule)
                  )
                }
                schedule={@quest.schedule}
              />
            <% end %>
            <%= if @trigger_preview == "once" do %>
              <div>
                <label class="text-sm font-medium">Run at</label>
                <input
                  type="datetime-local"
                  name="quest[run_at]"
                  class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background"
                />
              </div>
            <% end %>
            <%= if @trigger_preview == "source" do %>
              <.source_picker
                sources={@sources}
                namespace="quest"
                selected_ids={@quest.source_ids}
              />
            <% end %>
            <%= if @trigger_preview == "lore" do %>
              <div>
                <label class="text-sm font-medium">Trigger on tags</label>
                <input
                  type="text"
                  name="quest[lore_trigger_tags]"
                  value={Enum.join(@quest.lore_trigger_tags || [], ", ")}
                  placeholder="journal, decisions… (empty = all entries)"
                  class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                />
                <p class="text-xs text-muted-foreground mt-1">
                  Fires when a Grimoire entry with matching tags is created.
                </p>
              </div>
            <% end %>
            <div class="flex justify-end pt-1">
              <.button type="submit" size="sm" variant="outline">Save changes</.button>
            </div>
          </form>
          <div class="space-y-1.5 mt-4">
            <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Steps (in order)
            </p>
            <%= if @quest.steps == [] do %>
              <p class="text-sm text-muted-foreground italic">No steps added yet.</p>
            <% else %>
              <div class="rounded-md border divide-y divide-border">
                <%= for {step, idx} <- Enum.with_index(@quest.steps) do %>
                  <% step_struct =
                    Enum.find(@steps, &(to_string(&1.id) == to_string(step["step_id"]))) %>
                  <% sub_tags =
                    if step_struct do
                      case Enum.find(step_struct.context_providers || [], &(&1["type"] == "lore")) do
                        nil -> []
                        p -> p["tags"] || []
                      end
                    else
                      []
                    end %>
                  <% out_tags = if step_struct, do: step_struct.lore_tags || [], else: [] %>
                  <div class="text-sm px-3 py-2 bg-card hover:bg-muted/30">
                    <div class="flex items-center gap-2">
                      <span class="text-muted-foreground text-xs w-5 shrink-0 text-center select-none">
                        {idx + 1}
                      </span>
                      <span class="flex-1 truncate font-medium">
                        {quest_name_for_step(step, @steps)}
                      </span>
                      <div class="flex items-center gap-1 shrink-0">
                        <button
                          type="button"
                          class="inline-flex items-center justify-center h-7 w-7 rounded border text-xs font-bold transition-colors disabled:opacity-20 disabled:cursor-not-allowed disabled:pointer-events-none border-border text-muted-foreground hover:bg-muted hover:text-foreground"
                          phx-click="move_quest_step_up"
                          phx-value-quest_id={@quest.id}
                          phx-value-index={idx}
                          disabled={idx == 0}
                          aria-label="Move up"
                        >
                          ▲
                        </button>
                        <button
                          type="button"
                          class="inline-flex items-center justify-center h-7 w-7 rounded border text-xs font-bold transition-colors disabled:opacity-20 disabled:cursor-not-allowed disabled:pointer-events-none border-border text-muted-foreground hover:bg-muted hover:text-foreground"
                          phx-click="move_quest_step_down"
                          phx-value-quest_id={@quest.id}
                          phx-value-index={idx}
                          disabled={idx == length(@quest.steps) - 1}
                          aria-label="Move down"
                        >
                          ▼
                        </button>
                        <button
                          type="button"
                          class="inline-flex items-center justify-center h-7 w-7 rounded border text-xs transition-colors border-border text-muted-foreground hover:bg-destructive/10 hover:text-destructive hover:border-destructive/30"
                          phx-click="remove_quest_step"
                          phx-value-quest_id={@quest.id}
                          phx-value-index={idx}
                          aria-label="Remove"
                        >
                          ✕
                        </button>
                      </div>
                    </div>
                    <div class="ml-5 mt-1.5 grid grid-cols-2 gap-x-4 gap-y-1">
                      <form phx-submit="update_step_lore_tags" class="flex items-center gap-1">
                        <input type="hidden" name="step_id" value={step["step_id"]} />
                        <span class="text-xs text-muted-foreground shrink-0">Tags output:</span>
                        <input
                          type="text"
                          name="lore_tags"
                          value={Enum.join(out_tags, ", ")}
                          placeholder="journal, finance…"
                          class="flex-1 text-xs border-0 border-b border-border bg-transparent px-1 py-0.5 focus:outline-none focus:border-primary"
                        />
                      </form>
                      <form phx-submit="update_step_grimoire" class="flex items-center gap-1">
                        <input type="hidden" name="step_id" value={step["step_id"]} />
                        <span class="text-xs text-muted-foreground shrink-0">Reads from:</span>
                        <input
                          type="text"
                          name="tags"
                          value={Enum.join(sub_tags, ", ")}
                          placeholder="subscribe to tags…"
                          class="flex-1 text-xs border-0 border-b border-border bg-transparent px-1 py-0.5 focus:outline-none focus:border-primary"
                        />
                      </form>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
            <form phx-submit="add_quest_step" class="flex gap-2 mt-2">
              <input type="hidden" name="quest_id" value={@quest.id} />
              <select
                name="step_id"
                class="flex-1 text-sm border border-input rounded-md px-2 py-1 bg-background"
              >
                <option value="">Add step…</option>
                <%= for quest <- @steps do %>
                  <option value={quest.id}>{quest.name}</option>
                <% end %>
              </select>
              <.button type="submit" size="sm" variant="outline">Add</.button>
            </form>
          </div>

          <%= if @runs != [] do %>
            <div class="space-y-1.5 mt-4 pt-4 border-t">
              <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                Recent Runs
              </p>
              <div class="space-y-1">
                <%= for run <- Enum.take(@runs, 5) do %>
                  <div class="flex items-center gap-3 text-xs text-muted-foreground">
                    <span class={[
                      "shrink-0 font-medium",
                      run.status == "complete" && "text-green-600",
                      run.status == "failed" && "text-destructive",
                      run.status == "running" && "text-amber-500"
                    ]}>
                      {run.status}
                    </span>
                    <span class="text-muted-foreground/60">
                      {Calendar.strftime(run.inserted_at, "%b %d %H:%M")}
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp rebuild_trigger_previews(steps, quests, existing) do
    existing
    |> Map.merge(Map.new(steps, fn q -> {"step-#{q.id}", q.trigger} end))
    |> Map.merge(Map.new(quests, fn c -> {"quest-#{c.id}", c.trigger} end))
  end

  defp parse_schedule_info(nil), do: %{mode: "interval", interval: 1, unit: "hours", hour: 8, minute: 0, day: "1"}
  defp parse_schedule_info(""), do: %{mode: "interval", interval: 1, unit: "hours", hour: 8, minute: 0, day: "1"}

  defp parse_schedule_info(cron) do
    base = %{mode: "interval", interval: 1, unit: "hours", hour: 8, minute: 0, day: "1"}

    case String.split(cron) do
      ["*/" <> n, "*", "*", "*", "*"] -> %{base | mode: "interval", interval: String.to_integer(n), unit: "minutes"}
      ["0", "*/" <> n, "*", "*", "*"] -> %{base | mode: "interval", interval: String.to_integer(n), unit: "hours"}
      [m, h, "*", "*", "*"] -> %{base | mode: "daily", hour: to_int(h), minute: to_int(m)}
      [m, h, "*", "*", "1-5"] -> %{base | mode: "weekdays", hour: to_int(h), minute: to_int(m)}
      [m, h, "*", "*", d] -> %{base | mode: "weekly", hour: to_int(h), minute: to_int(m), day: d}
      [m, h, d, "*", "*"] -> %{base | mode: "monthly", hour: to_int(h), minute: to_int(m), day: d}
      _ -> base
    end
  end

  defp to_int(s), do: String.to_integer(s)

  defp detect_schedule_mode(schedule) do
    %{mode: mode} = parse_schedule_info(schedule)
    mode
  end

  defp build_schedule_from_params(params) do
    case params["schedule_mode"] do
      "daily" ->
        "#{params["schedule_minute"] || "0"} #{params["schedule_hour"] || "8"} * * *"

      "weekdays" ->
        "#{params["schedule_minute"] || "0"} #{params["schedule_hour"] || "8"} * * 1-5"

      "weekly" ->
        "#{params["schedule_minute"] || "0"} #{params["schedule_hour"] || "8"} * * #{params["schedule_day"] || "1"}"

      "monthly" ->
        "#{params["schedule_minute"] || "0"} #{params["schedule_hour"] || "8"} #{params["schedule_day"] || "1"} * *"

      _ ->
        interval = String.to_integer(params["schedule_interval"] || "1")
        build_schedule(interval, params["schedule_unit"] || "hours")
    end
  end

  defp build_schedule(interval, "minutes"), do: "*/#{interval} * * * *"
  defp build_schedule(interval, "hours"), do: "0 */#{interval} * * *"
  defp build_schedule(_, _), do: nil

  defp build_schedule_mode_previews(quests) do
    quests
    |> Map.new(fn q -> {"quest-#{q.id}", detect_schedule_mode(q.schedule)} end)
    |> Map.put("new-quest", "interval")
  end

  defp hour_label(h) do
    case h do
      0 -> "12am"
      12 -> "12pm"
      h when h < 12 -> "#{h}am"
      h -> "#{h - 12}pm"
    end
  end

  defp assign_quests(socket) do
    assign(socket, quests: Quests.list_quests())
  end

  defp assign_steps(socket) do
    assign(socket, steps: Quests.list_steps())
  end

  defp board_with_status(template) do
    requirements = Board.check_requirements(template)
    readiness = Board.readiness(template)
    %{template: template, requirements: requirements, readiness: readiness}
  end

  defp board_tab_category("all"), do: nil
  defp board_tab_category("custom"), do: nil
  defp board_tab_category(tab), do: String.to_existing_atom(tab)

  defp board_visible(templates, category, show_unavailable) do
    Enum.filter(templates, fn %{template: t, readiness: r} ->
      category_match = is_nil(category) || t.category == category
      availability_match = show_unavailable || r != :unavailable
      category_match && availability_match
    end)
  end

  defp board_category_label(cat) do
    labels = [
      triage: "Triage",
      reporting: "Reporting",
      generation: "Generation",
      review: "Review",
      onboarding: "Onboarding",
      lifestyle: "Lifestyle"
    ]

    labels[cat] || to_string(cat)
  end

  defp board_readiness_badge(:ready), do: {"Ready", "default"}
  defp board_readiness_badge(:almost), do: {"Almost", "secondary"}
  defp board_readiness_badge(:unavailable), do: {"Missing", "outline"}

  defp source_label(%Source{name: name}) when is_binary(name) and name != "", do: name

  defp source_label(%Source{book_id: book_id}) when is_binary(book_id) do
    case Book.get(book_id) do
      nil -> book_id
      book -> book.name
    end
  end

  defp source_label(%Source{source_type: type}), do: String.capitalize(type) <> " source"

  defp trigger_label("source"), do: "Library Source"
  defp trigger_label("lore"), do: "Grimoire"
  defp trigger_label("once"), do: "Once"
  defp trigger_label("scheduled"), do: "Scheduled"
  defp trigger_label("manual"), do: "Manual"
  defp trigger_label(other), do: other

  defp quest_name_for_step(step, steps) do
    case step["step_id"] do
      nil -> "(deleted step)"
      id -> Enum.find_value(steps, "(deleted step)", &(to_string(&1.id) == to_string(id) && &1.name))
    end
  end
end
