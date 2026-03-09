defmodule ExCaliburWeb.QuestsLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge

  alias Excellence.Schemas.Member
  alias ExCalibur.Quests
  alias ExCalibur.Quests.Quest
  alias ExCalibur.Sources.Book
  alias ExCalibur.Sources.Source

  @impl true
  def mount(_params, _session, socket) do
    import Ecto.Query
    quests = Quests.list_quests()
    campaigns = Quests.list_campaigns()
    sources = ExCalibur.Repo.all(from(s in Source, order_by: [asc: s.inserted_at]))

    trigger_previews =
      Map.new(quests, fn q -> {"quest-#{q.id}", q.trigger} end)
      |> Map.merge(Map.new(campaigns, fn c -> {"campaign-#{c.id}", c.trigger} end))
      |> Map.put("new-quest", "manual")
      |> Map.put("new-campaign", "manual")

    output_previews =
      quests
      |> Map.new(fn q -> {"quest-#{q.id}", q.output_type || "verdict"} end)
      |> Map.put("new-quest", "verdict")

    context_previews =
      quests
      |> Map.new(fn q ->
        type =
          case q.context_providers do
            [%{"type" => t} | _] -> t
            _ -> "none"
          end

        {"quest-#{q.id}", type}
      end)
      |> Map.put("new-quest", "none")

    write_mode_previews =
      quests
      |> Map.new(fn q -> {"quest-#{q.id}", q.write_mode || "append"} end)
      |> Map.put("new-quest", "append")

    {:ok,
     assign(socket,
       quests: quests,
       campaigns: campaigns,
       teams: list_teams(),
       sources: sources,
       heralds: ExCalibur.Heralds.list_heralds(),
       expanded: MapSet.new(),
       adding_quest: false,
       adding_campaign: false,
       running: %{},
       quest_runs: %{},
       trigger_previews: trigger_previews,
       output_previews: output_previews,
       context_previews: context_previews,
       write_mode_previews: write_mode_previews
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Quests")}
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
  def handle_event("add_quest", _, socket) do
    {:noreply, assign(socket, adding_quest: true, adding_campaign: false)}
  end

  @impl true
  def handle_event("add_campaign", _, socket) do
    {:noreply, assign(socket, adding_campaign: true, adding_quest: false)}
  end

  @impl true
  def handle_event("cancel_new", _, socket) do
    {:noreply, assign(socket, adding_quest: false, adding_campaign: false)}
  end

  @impl true
  def handle_event("preview_quest_trigger", %{"quest_id" => id} = params, socket) do
    t = get_in(params, ["quest", "trigger"])
    o = get_in(params, ["quest", "output_type"])
    c = get_in(params, ["quest", "context_type"])
    wm = get_in(params, ["quest", "write_mode"])

    socket =
      if t,
        do: assign(socket, trigger_previews: Map.put(socket.assigns.trigger_previews, "quest-#{id}", t)),
        else: socket

    socket =
      if o,
        do: assign(socket, output_previews: Map.put(socket.assigns.output_previews, "quest-#{id}", o)),
        else: socket

    socket =
      if c,
        do: assign(socket, context_previews: Map.put(socket.assigns.context_previews, "quest-#{id}", c)),
        else: socket

    socket =
      if wm,
        do: assign(socket, write_mode_previews: Map.put(socket.assigns.write_mode_previews, "quest-#{id}", wm)),
        else: socket

    {:noreply, socket}
  end

  def handle_event("preview_quest_trigger", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("preview_new_quest_trigger", params, socket) do
    t = get_in(params, ["quest", "trigger"])
    o = get_in(params, ["quest", "output_type"])
    c = get_in(params, ["quest", "context_type"])
    wm = get_in(params, ["quest", "write_mode"])

    socket =
      if t,
        do: assign(socket, trigger_previews: Map.put(socket.assigns.trigger_previews, "new-quest", t)),
        else: socket

    socket =
      if o,
        do: assign(socket, output_previews: Map.put(socket.assigns.output_previews, "new-quest", o)),
        else: socket

    socket =
      if c,
        do: assign(socket, context_previews: Map.put(socket.assigns.context_previews, "new-quest", c)),
        else: socket

    socket =
      if wm,
        do: assign(socket, write_mode_previews: Map.put(socket.assigns.write_mode_previews, "new-quest", wm)),
        else: socket

    {:noreply, socket}
  end

  @impl true
  def handle_event("preview_campaign_trigger", %{"campaign_id" => id, "campaign" => %{"trigger" => t}}, socket) do
    {:noreply, assign(socket, trigger_previews: Map.put(socket.assigns.trigger_previews, "campaign-#{id}", t))}
  end

  def handle_event("preview_campaign_trigger", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("preview_new_campaign_trigger", %{"campaign" => %{"trigger" => t}}, socket) do
    {:noreply, assign(socket, trigger_previews: Map.put(socket.assigns.trigger_previews, "new-campaign", t))}
  end

  def handle_event("preview_new_campaign_trigger", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("move_campaign_quest_up", %{"campaign_id" => id, "index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    campaign = Quests.get_campaign!(String.to_integer(id))
    steps = campaign.steps
    {a, b} = {Enum.at(steps, idx - 1), Enum.at(steps, idx)}
    new_steps = steps |> List.replace_at(idx - 1, b) |> List.replace_at(idx, a)
    Quests.update_campaign(campaign, %{steps: new_steps})
    {:noreply, assign(socket, campaigns: Quests.list_campaigns())}
  end

  @impl true
  def handle_event("move_campaign_quest_down", %{"campaign_id" => id, "index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    campaign = Quests.get_campaign!(String.to_integer(id))
    steps = campaign.steps
    {a, b} = {Enum.at(steps, idx), Enum.at(steps, idx + 1)}
    new_steps = steps |> List.replace_at(idx, b) |> List.replace_at(idx + 1, a)
    Quests.update_campaign(campaign, %{steps: new_steps})
    {:noreply, assign(socket, campaigns: Quests.list_campaigns())}
  end

  @impl true
  def handle_event("remove_campaign_quest", %{"campaign_id" => id, "index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    campaign = Quests.get_campaign!(String.to_integer(id))
    new_steps = List.delete_at(campaign.steps, idx)
    Quests.update_campaign(campaign, %{steps: new_steps})
    {:noreply, assign(socket, campaigns: Quests.list_campaigns())}
  end

  @impl true
  def handle_event("add_campaign_quest", %{"campaign_id" => _id, "quest_id" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("add_campaign_quest", %{"campaign_id" => id, "quest_id" => quest_id}, socket) do
    campaign = Quests.get_campaign!(String.to_integer(id))
    new_step = %{"quest_id" => quest_id, "flow" => "always"}
    Quests.update_campaign(campaign, %{steps: campaign.steps ++ [new_step]})
    {:noreply, assign(socket, campaigns: Quests.list_campaigns())}
  end

  @impl true
  def handle_event("create_quest", %{"quest" => params}, socket) do
    escalate_on =
      case params["escalate_on"] do
        "warn_or_fail" -> %{"type" => "verdict", "values" => ["warn", "fail"]}
        "fail_only" -> %{"type" => "verdict", "values" => ["fail"]}
        "always" -> "always"
        _ -> "never"
      end

    roster = [
      %{
        "who" => params["who"] || "all",
        "when" => "on_trigger",
        "how" => params["how"] || "consensus",
        "escalate_on" => escalate_on
      }
    ]

    context_providers =
      case params["context_type"] do
        "static" ->
          content = String.trim(params["context_content"] || "")
          if content == "", do: [], else: [%{"type" => "static", "content" => content}]

        "quest_history" ->
          [%{"type" => "quest_history", "limit" => 5}]

        "member_stats" ->
          [%{"type" => "member_stats"}]

        "lore" ->
          tags =
            (params["kb_tags"] || "")
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          limit =
            case Integer.parse(params["kb_limit"] || "10") do
              {n, _} -> max(1, n)
              _ -> 10
            end

          sort = params["kb_sort"] || "newest"
          [%{"type" => "lore", "tags" => tags, "limit" => limit, "sort" => sort}]

        _ ->
          []
      end

    trigger = params["trigger"] || "manual"

    schedule =
      if trigger == "scheduled" do
        interval = String.to_integer(params["schedule_interval"] || "1")
        build_schedule(interval, params["schedule_unit"] || "hours")
      end

    source_ids = if trigger == "source", do: params |> Map.get("source_ids", []) |> List.wrap(), else: []

    output_type = params["output_type"] || "verdict"
    write_mode = if output_type == "artifact", do: params["write_mode"] || "append", else: "append"
    entry_title_template = if output_type == "artifact", do: params["entry_title_template"], else: nil
    log_title_template = if output_type == "artifact", do: params["log_title_template"], else: nil
    herald_name = if output_type in ~w(slack webhook github_issue github_pr email pagerduty), do: params["herald_name"], else: nil

    attrs = %{
      name: params["name"],
      description: params["description"],
      trigger: trigger,
      schedule: schedule,
      source_ids: source_ids,
      roster: roster,
      context_providers: context_providers,
      status: "active",
      output_type: output_type,
      write_mode: write_mode,
      entry_title_template: entry_title_template,
      log_title_template: log_title_template,
      herald_name: herald_name
    }

    case Quests.create_quest(attrs) do
      {:ok, _} ->
        quests = Quests.list_quests()
        previews = rebuild_trigger_previews(quests, socket.assigns.campaigns, socket.assigns.trigger_previews)
        output_previews = rebuild_output_previews(quests, socket.assigns.output_previews)
        context_previews = rebuild_context_previews(quests, socket.assigns.context_previews)
        write_mode_previews = rebuild_write_mode_previews(quests, socket.assigns.write_mode_previews)
        {:noreply, assign(socket, quests: quests, adding_quest: false, trigger_previews: previews, output_previews: output_previews, context_previews: context_previews, write_mode_previews: write_mode_previews)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create quest")}
    end
  end

  @impl true
  def handle_event("create_campaign", %{"campaign" => params}, socket) do
    quest_ids = params |> Map.get("quest_ids", []) |> List.wrap()
    steps = Enum.map(quest_ids, &%{"quest_id" => &1, "flow" => "always"})
    trigger = params["trigger"] || "manual"

    schedule =
      if trigger == "scheduled" do
        interval = String.to_integer(params["schedule_interval"] || "1")
        build_schedule(interval, params["schedule_unit"] || "hours")
      end

    source_ids = if trigger == "source", do: params |> Map.get("source_ids", []) |> List.wrap(), else: []

    attrs = %{
      name: params["name"],
      description: params["description"],
      trigger: trigger,
      schedule: schedule,
      source_ids: source_ids,
      steps: steps,
      status: "active"
    }

    case Quests.create_campaign(attrs) do
      {:ok, _} ->
        campaigns = Quests.list_campaigns()
        previews = rebuild_trigger_previews(socket.assigns.quests, campaigns, socket.assigns.trigger_previews)
        {:noreply, assign(socket, campaigns: campaigns, adding_campaign: false, trigger_previews: previews)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create campaign")}
    end
  end

  @impl true
  def handle_event("update_campaign", %{"campaign" => params, "campaign_id" => id}, socket) do
    campaign = Quests.get_campaign!(String.to_integer(id))
    trigger = params["trigger"] || "manual"

    schedule =
      if trigger == "scheduled" do
        interval = String.to_integer(params["schedule_interval"] || "1")
        build_schedule(interval, params["schedule_unit"] || "hours")
      end

    source_ids = if trigger == "source", do: params |> Map.get("source_ids", []) |> List.wrap(), else: []

    attrs = %{
      name: params["name"],
      description: params["description"],
      trigger: trigger,
      schedule: schedule,
      source_ids: source_ids
    }

    case Quests.update_campaign(campaign, attrs) do
      {:ok, _} ->
        campaigns = Quests.list_campaigns()
        previews = rebuild_trigger_previews(socket.assigns.quests, campaigns, socket.assigns.trigger_previews)
        {:noreply, assign(socket, campaigns: campaigns, trigger_previews: previews)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update campaign")}
    end
  end

  @impl true
  def handle_event("toggle_quest_status", %{"id" => id}, socket) do
    quest = Quests.get_quest!(String.to_integer(id))
    new_status = if quest.status == "active", do: "paused", else: "active"
    Quests.update_quest(quest, %{status: new_status})
    {:noreply, assign(socket, quests: Quests.list_quests())}
  end

  @impl true
  def handle_event("toggle_campaign_status", %{"id" => id}, socket) do
    campaign = Quests.get_campaign!(String.to_integer(id))
    new_status = if campaign.status == "active", do: "paused", else: "active"
    Quests.update_campaign(campaign, %{status: new_status})
    {:noreply, assign(socket, campaigns: Quests.list_campaigns())}
  end

  @impl true
  def handle_event("delete_quest", %{"id" => id}, socket) do
    quest = Quests.get_quest!(String.to_integer(id))
    Quests.delete_quest(quest)
    {:noreply, assign(socket, quests: Quests.list_quests())}
  end

  @impl true
  def handle_event("delete_campaign", %{"id" => id}, socket) do
    campaign = Quests.get_campaign!(String.to_integer(id))
    Quests.delete_campaign(campaign)
    {:noreply, assign(socket, campaigns: Quests.list_campaigns())}
  end

  @impl true
  def handle_event("run_quest", %{"quest_id" => id, "input" => input}, socket) when input != "" do
    quest = Quests.get_quest!(String.to_integer(id))
    run_id = to_string(quest.id)

    {:ok, quest_run} =
      Quests.create_quest_run(%{quest_id: quest.id, input: input, status: "running"})

    running = Map.put(socket.assigns.running, run_id, %{status: "running", result: nil})
    parent = self()

    Task.start(fn ->
      result = ExCalibur.QuestRunner.run(quest, input)
      send(parent, {:quest_run_complete, run_id, quest_run.id, result})
    end)

    {:noreply,
     socket
     |> assign(running: running)
     |> push_event("reset-form", %{id: "run-form-#{quest.id}"})}
  end

  def handle_event("run_quest", _, socket) do
    {:noreply, put_flash(socket, :error, "Please enter some input to evaluate")}
  end

  @impl true
  def handle_event("update_quest", %{"quest" => params, "quest_id" => id}, socket) do
    quest = Quests.get_quest!(String.to_integer(id))

    escalate_on =
      case params["escalate_on"] do
        "warn_or_fail" -> %{"type" => "verdict", "values" => ["warn", "fail"]}
        "fail_only" -> %{"type" => "verdict", "values" => ["fail"]}
        "always" -> "always"
        _ -> "never"
      end

    roster = [
      %{
        "who" => params["who"] || "all",
        "when" => "on_trigger",
        "how" => params["how"] || "consensus",
        "escalate_on" => escalate_on
      }
    ]

    context_providers =
      case params["context_type"] do
        "static" ->
          content = String.trim(params["context_content"] || "")
          if content == "", do: [], else: [%{"type" => "static", "content" => content}]

        "quest_history" ->
          [%{"type" => "quest_history", "limit" => 5}]

        "member_stats" ->
          [%{"type" => "member_stats"}]

        "lore" ->
          tags =
            (params["kb_tags"] || "")
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          limit =
            case Integer.parse(params["kb_limit"] || "10") do
              {n, _} -> max(1, n)
              _ -> 10
            end

          sort = params["kb_sort"] || "newest"
          [%{"type" => "lore", "tags" => tags, "limit" => limit, "sort" => sort}]

        _ ->
          []
      end

    trigger = params["trigger"] || "manual"

    schedule =
      if trigger == "scheduled" do
        interval = String.to_integer(params["schedule_interval"] || "1")
        build_schedule(interval, params["schedule_unit"] || "hours")
      end

    source_ids = if trigger == "source", do: params |> Map.get("source_ids", []) |> List.wrap(), else: []

    output_type = params["output_type"] || "verdict"
    write_mode = if output_type == "artifact", do: params["write_mode"] || "append", else: "append"
    entry_title_template = if output_type == "artifact", do: params["entry_title_template"], else: nil
    log_title_template = if output_type == "artifact", do: params["log_title_template"], else: nil
    herald_name = if output_type in ~w(slack webhook github_issue github_pr email pagerduty), do: params["herald_name"], else: nil

    attrs = %{
      name: params["name"],
      description: params["description"],
      trigger: trigger,
      schedule: schedule,
      source_ids: source_ids,
      roster: roster,
      context_providers: context_providers,
      output_type: output_type,
      write_mode: write_mode,
      entry_title_template: entry_title_template,
      log_title_template: log_title_template,
      herald_name: herald_name
    }

    case Quests.update_quest(quest, attrs) do
      {:ok, _} ->
        quests = Quests.list_quests()
        previews = rebuild_trigger_previews(quests, socket.assigns.campaigns, socket.assigns.trigger_previews)
        output_previews = rebuild_output_previews(quests, socket.assigns.output_previews)
        context_previews = rebuild_context_previews(quests, socket.assigns.context_previews)
        write_mode_previews = rebuild_write_mode_previews(quests, socket.assigns.write_mode_previews)
        {:noreply, assign(socket, quests: quests, trigger_previews: previews, output_previews: output_previews, context_previews: context_previews, write_mode_previews: write_mode_previews)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update quest")}
    end
  end

  @impl true
  def handle_info({:quest_run_complete, run_id, quest_run_id, result}, socket) do
    {status, results} =
      case result do
        {:ok, outcome} -> {"complete", outcome}
        {:error, reason} -> {"failed", %{error: inspect(reason)}}
      end

    quest_run = ExCalibur.Repo.get!(ExCalibur.Quests.QuestRun, quest_run_id)
    {:ok, updated_run} = Quests.update_quest_run(quest_run, %{status: status, results: results})

    if status == "complete" do
      quest = Quests.get_quest!(updated_run.quest_id)
      Task.start(fn -> ExCalibur.LearningLoop.retrospect(quest, updated_run) end)
    end

    running = Map.put(socket.assigns.running, run_id, %{status: status, result: results})

    quest_runs =
      Map.put(
        socket.assigns.quest_runs,
        run_id,
        Quests.list_quest_runs(Quests.get_quest!(updated_run.quest_id))
      )

    {:noreply, assign(socket, running: running, quest_runs: quest_runs)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-10">
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Quests</h1>
        <p class="text-muted-foreground mt-1.5">
          Evaluation pipelines — configure who runs them, how, and on what trigger.
        </p>
      </div>

      <div>
        <div class="flex items-center justify-between mb-1">
          <h2 class="text-lg font-semibold">Campaigns</h2>
          <.button variant="outline" size="sm" phx-click="add_campaign">+ Campaign</.button>
        </div>
        <p class="text-sm text-muted-foreground mb-5">
          Ordered sequences of quests run together.
        </p>
        <%= if @adding_campaign do %>
          <div class="mb-3">
            <.new_campaign_form quests={@quests} sources={@sources} trigger_preview={@trigger_previews["new-campaign"] || "manual"} />
          </div>
        <% end %>
        <div class="space-y-3">
          <.campaign_card
            :for={campaign <- @campaigns}
            campaign={campaign}
            quests={@quests}
            sources={@sources}
            expanded={MapSet.member?(@expanded, "campaign-#{campaign.id}")}
            trigger_preview={@trigger_previews["campaign-#{campaign.id}"] || campaign.trigger}
          />
        </div>
      </div>

      <div>
        <div class="flex items-center justify-between mb-1">
          <h2 class="text-lg font-semibold">Quests</h2>
          <.button variant="outline" size="sm" phx-click="add_quest">+ Quest</.button>
        </div>
        <p class="text-sm text-muted-foreground mb-5">
          Individual evaluation runs — trigger manually, on a schedule, or from a source.
        </p>
        <%= if @adding_quest do %>
          <div class="mb-3">
            <.new_quest_form
              teams={@teams}
              sources={@sources}
              heralds={@heralds}
              trigger_preview={@trigger_previews["new-quest"] || "manual"}
              output_preview={@output_previews["new-quest"] || "verdict"}
              context_preview={@context_previews["new-quest"] || "none"}
              write_mode_preview={@write_mode_previews["new-quest"] || "append"}
            />
          </div>
        <% end %>
        <div class="space-y-3">
          <.quest_card
            :for={quest <- @quests}
            quest={quest}
            expanded={MapSet.member?(@expanded, "quest-#{quest.id}")}
            run_state={Map.get(@running, to_string(quest.id))}
            past_runs={Map.get(@quest_runs, to_string(quest.id), [])}
            teams={@teams}
            sources={@sources}
            heralds={@heralds}
            trigger_preview={@trigger_previews["quest-#{quest.id}"] || quest.trigger}
            output_preview={@output_previews["quest-#{quest.id}"] || quest.output_type || "verdict"}
            context_preview={@context_previews["quest-#{quest.id}"] || "none"}
            write_mode_preview={@write_mode_previews["quest-#{quest.id}"] || quest.write_mode || "append"}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :teams, :list, default: []
  attr :sources, :list, default: []
  attr :heralds, :list, default: []
  attr :trigger_preview, :string, default: "manual"
  attr :output_preview, :string, default: "verdict"
  attr :context_preview, :string, default: "none"
  attr :write_mode_preview, :string, default: "append"

  defp new_quest_form(assigns) do
    ~H"""
    <div class="border rounded-lg border-dashed p-4">
      <form phx-submit="create_quest" phx-change="preview_new_quest_trigger" class="space-y-3">
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <label class="text-sm font-medium">Name</label>
            <.input type="text" name="quest[name]" value="" placeholder="e.g. WCAG Hourly Scan" />
          </div>
          <div>
            <label class="text-sm font-medium">Description</label>
            <.input type="text" name="quest[description]" value="" placeholder="Optional" />
          </div>
        </div>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 md:grid-cols-4">
          <div>
            <label for="quest-who" class="text-sm font-medium">Who runs it</label>
            <select id="quest-who" name="quest[who]" class="w-full text-sm border rounded px-2 py-1 bg-background">
              <option value="all">Everyone</option>
              <option value="apprentice">Apprentice tier</option>
              <option value="journeyman">Journeyman tier</option>
              <option value="master">Master tier</option>
              <optgroup label="Cloud escalation">
                <option value="claude_haiku">Claude Haiku</option>
                <option value="claude_sonnet">Claude Sonnet</option>
                <option value="claude_opus">Claude Opus</option>
              </optgroup>
              <%= if @teams != [] do %>
                <optgroup label="Teams">
                  <%= for team <- @teams do %>
                    <option value={"team:#{team}"}>{team}</option>
                  <% end %>
                </optgroup>
              <% end %>
            </select>
          </div>
          <div>
            <label for="quest-how" class="text-sm font-medium">How</label>
            <select id="quest-how" name="quest[how]" class="w-full text-sm border rounded px-2 py-1 bg-background">
              <option value="consensus">Consensus</option>
              <option value="solo">Solo</option>
              <option value="majority">Majority</option>
            </select>
          </div>
          <div>
            <label for="quest-escalate-on" class="text-sm font-medium">Escalate on</label>
            <select
              id="quest-escalate-on"
              name="quest[escalate_on]"
              class="w-full text-sm border rounded px-2 py-1 bg-background"
            >
              <option value="never">Never</option>
              <option value="warn_or_fail">Warn or fail</option>
              <option value="fail_only">Fail only</option>
              <option value="always">Always</option>
            </select>
          </div>
          <div>
            <label for="quest-trigger-new" class="text-sm font-medium">Trigger</label>
            <select
              id="quest-trigger-new"
              name="quest[trigger]"
              class="w-full text-sm border rounded px-2 py-1 bg-background"
            >
              <option value="manual">Manual</option>
              <option value="source">Source</option>
              <option value="scheduled">Scheduled</option>
            </select>
          </div>
        </div>
        <%= if @trigger_preview == "scheduled" do %>
          <.schedule_picker unit="hours" interval={1} id_prefix="new-quest" />
        <% end %>
        <%= if @trigger_preview == "source" do %>
          <.source_picker sources={@sources} namespace="quest" selected_ids={[]} />
        <% end %>
        <div>
          <label for="quest-context-type" class="text-sm font-medium">Context (optional)</label>
          <div class="mt-1 space-y-1">
            <select
              id="quest-context-type"
              name="quest[context_type]"
              class="w-full text-sm border rounded px-2 py-1 bg-background"
            >
              <option value="">None</option>
              <option value="static">Static text</option>
              <option value="quest_history">Quest history</option>
              <option value="member_stats">Member roster</option>
              <option value="lore">Knowledge board</option>
            </select>
            <.input
              type="textarea"
              name="quest[context_content]"
              value=""
              rows={2}
              placeholder="Static context text (if Static selected)"
            />
            <%= if @context_preview == "lore" do %>
              <div class="grid grid-cols-3 gap-2 mt-1">
                <div>
                  <label class="text-xs text-muted-foreground">Tags (comma-sep)</label>
                  <input
                    type="text"
                    name="quest[kb_tags]"
                    placeholder="a11y, security"
                    class="w-full h-8 text-sm border border-input rounded-md px-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                  />
                </div>
                <div>
                  <label class="text-xs text-muted-foreground">Limit</label>
                  <input
                    type="number"
                    name="quest[kb_limit]"
                    value="10"
                    min="1"
                    class="w-full h-8 text-sm border border-input rounded-md px-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                  />
                </div>
                <div>
                  <label class="text-xs text-muted-foreground">Sort</label>
                  <select
                    name="quest[kb_sort]"
                    class="w-full h-8 text-sm border border-input rounded-md px-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                  >
                    <option value="newest">Newest</option>
                    <option value="importance">Importance</option>
                  </select>
                </div>
              </div>
            <% end %>
          </div>
        </div>
        <div>
          <label class="text-sm font-medium">Output</label>
          <select
            name="quest[output_type]"
            class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
          >
            <option value="verdict" selected={@output_preview == "verdict"}>
              Verdict (pass/warn/fail)
            </option>
            <option value="artifact" selected={@output_preview == "artifact"}>
              Artifact (write to Grimoire)
            </option>
            <optgroup label="Heralds">
              <option value="slack" selected={@output_preview == "slack"}>Slack</option>
              <option value="webhook" selected={@output_preview == "webhook"}>Webhook</option>
              <option value="github_issue" selected={@output_preview == "github_issue"}>GitHub Issue</option>
              <option value="github_pr" selected={@output_preview == "github_pr"}>GitHub PR</option>
              <option value="email" selected={@output_preview == "email"}>Email</option>
              <option value="pagerduty" selected={@output_preview == "pagerduty"}>PagerDuty</option>
            </optgroup>
          </select>
        </div>
        <%= if @output_preview == "artifact" do %>
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div>
              <label class="text-sm font-medium">Write mode</label>
              <select
                name="quest[write_mode]"
                class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
              >
                <option value="append" selected={@write_mode_preview == "append"}>Append (each run adds an entry)</option>
                <option value="replace" selected={@write_mode_preview == "replace"}>Replace (overwrite previous entry)</option>
                <option value="both" selected={@write_mode_preview == "both"}>Both (update summary + append log)</option>
              </select>
            </div>
            <div>
              <label class="text-sm font-medium">Title template</label>
              <input
                type="text"
                name="quest[entry_title_template]"
                placeholder="Summary — {date}"
                class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
              />
            </div>
          </div>
          <%= if @write_mode_preview == "both" do %>
            <div>
              <label class="text-sm font-medium">Log title template</label>
              <input
                type="text"
                name="quest[log_title_template]"
                value=""
                placeholder="Log — {date}"
                class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
              />
            </div>
          <% end %>
        <% end %>
        <%= if @output_preview in ~w(slack webhook github_issue github_pr email pagerduty) do %>
          <% type_heralds = Enum.filter(@heralds, &(&1.type == @output_preview)) %>
          <div>
            <label class="text-sm font-medium">Herald</label>
            <%= if type_heralds == [] do %>
              <p class="text-xs text-muted-foreground mt-1">
                No <strong>{@output_preview}</strong> heralds configured.
                <a href="/library" class="underline">Add one in Library → Heralds.</a>
              </p>
            <% else %>
              <select
                name="quest[herald_name]"
                class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
              >
                <%= for h <- type_heralds do %>
                  <option value={h.name}>{h.name}</option>
                <% end %>
              </select>
            <% end %>
          </div>
        <% end %>
        <div class="flex justify-end gap-2">
          <.button type="button" variant="outline" size="sm" phx-click="cancel_new">
            Cancel
          </.button>
          <.button type="submit" size="sm">Create Quest</.button>
        </div>
      </form>
    </div>
    """
  end

  attr :id_prefix, :string, required: true
  attr :namespace, :string, default: "quest"
  attr :unit, :string, default: "hours"
  attr :interval, :integer, default: 1

  defp schedule_picker(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-sm text-muted-foreground shrink-0">Every</span>
      <input
        type="number"
        name={@namespace <> "[schedule_interval]"}
        value={@interval}
        min="1"
        class="w-20 h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
      />
      <select
        id={"schedule-unit-#{@id_prefix}"}
        name={@namespace <> "[schedule_unit]"}
        class="h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
      >
        <option value="minutes" selected={@unit == "minutes"}>minutes</option>
        <option value="hours" selected={@unit == "hours"}>hours</option>
      </select>
    </div>
    """
  end

  attr :sources, :list, default: []
  attr :namespace, :string, default: "quest"
  attr :selected_ids, :list, default: []

  defp source_picker(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <p class="text-sm font-medium">Sources</p>
      <%= if @sources == [] do %>
        <p class="text-xs text-muted-foreground">
          No active sources. <a href="/stacks" class="underline">Add sources in Stacks.</a>
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

  attr :quests, :list, required: true
  attr :sources, :list, default: []
  attr :trigger_preview, :string, default: "manual"

  defp new_campaign_form(assigns) do
    ~H"""
    <div class="border rounded-lg border-dashed p-4">
      <form phx-submit="create_campaign" phx-change="preview_new_campaign_trigger" class="space-y-3">
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <label class="text-sm font-medium">Name</label>
            <.input type="text" name="campaign[name]" value="" placeholder="e.g. Monthly Audit" />
          </div>
          <div>
            <label class="text-sm font-medium">Description</label>
            <.input type="text" name="campaign[description]" value="" placeholder="Optional" />
          </div>
        </div>
        <div>
          <label for="campaign-trigger-new" class="text-sm font-medium">Trigger</label>
          <select
            id="campaign-trigger-new"
            name="campaign[trigger]"
            class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
          >
            <option value="manual">Manual</option>
            <option value="source">Source</option>
            <option value="scheduled">Scheduled</option>
          </select>
        </div>
        <%= if @trigger_preview == "scheduled" do %>
          <.schedule_picker namespace="campaign" unit="hours" interval={1} id_prefix="new-campaign" />
        <% end %>
        <%= if @trigger_preview == "source" do %>
          <.source_picker sources={@sources} namespace="campaign" selected_ids={[]} />
        <% end %>
        <div>
          <label class="text-sm font-medium">Quests (select in order)</label>
          <select
            name="campaign[quest_ids][]"
            multiple
            class="w-full text-sm border rounded px-2 py-1 bg-background h-24"
          >
            <%= for quest <- @quests do %>
              <option value={quest.id}>{quest.name}</option>
            <% end %>
          </select>
          <p class="text-xs text-muted-foreground mt-1">Hold Ctrl/Cmd to select multiple</p>
        </div>
        <div class="flex justify-end gap-2">
          <.button type="button" variant="outline" size="sm" phx-click="cancel_new">
            Cancel
          </.button>
          <.button type="submit" size="sm">Create Campaign</.button>
        </div>
      </form>
    </div>
    """
  end

  attr :campaign, :map, required: true
  attr :quests, :list, required: true
  attr :sources, :list, default: []
  attr :expanded, :boolean, required: true
  attr :trigger_preview, :string, required: true

  defp campaign_card(assigns) do
    ~H"""
    <div class={["border rounded-lg bg-card", if(@campaign.status == "paused", do: "opacity-60")]}>
      <div class="flex items-center gap-3 px-5 py-4">
        <div
          class="flex flex-1 items-center gap-3 cursor-pointer min-w-0"
          phx-click="toggle_expand"
          phx-value-id={"campaign-#{@campaign.id}"}
        >
          <span class={[
            "transition-transform text-muted-foreground",
            if(@expanded, do: "rotate-90")
          ]}>
            ›
          </span>
          <div class="flex-1 min-w-0">
            <span class="font-medium">{@campaign.name}</span>
            <span class="text-xs text-muted-foreground ml-2">
              {length(@campaign.steps)} quests
            </span>
          </div>
          <.badge variant="outline" class="text-xs shrink-0">{@campaign.trigger}</.badge>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <.button
            size="sm"
            variant="ghost"
            phx-click="toggle_campaign_status"
            phx-value-id={@campaign.id}
          >
            {if @campaign.status == "active", do: "Pause", else: "Resume"}
          </.button>
          <.button
            size="sm"
            variant="ghost"
            phx-click="delete_campaign"
            phx-value-id={@campaign.id}
            data-confirm="Delete this campaign?"
          >
            Delete
          </.button>
        </div>
      </div>
      <%= if @expanded do %>
        <div class="border-t px-5 py-5">
          <form phx-submit="update_campaign" phx-change="preview_campaign_trigger" class="space-y-4">
            <input type="hidden" name="campaign_id" value={@campaign.id} />
            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div class="space-y-1.5">
                <label for={"cname-#{@campaign.id}"} class="text-sm font-medium">Name</label>
                <.input
                  id={"cname-#{@campaign.id}"}
                  type="text"
                  name="campaign[name]"
                  value={@campaign.name}
                />
              </div>
              <div class="space-y-1.5">
                <label for={"cdesc-#{@campaign.id}"} class="text-sm font-medium">Description</label>
                <.input
                  id={"cdesc-#{@campaign.id}"}
                  type="text"
                  name="campaign[description]"
                  value={@campaign.description || ""}
                  placeholder="Optional"
                />
              </div>
            </div>
            <div class="space-y-1.5">
              <label for={"ctrigger-#{@campaign.id}"} class="text-sm font-medium">Trigger</label>
              <select
                id={"ctrigger-#{@campaign.id}"}
                name="campaign[trigger]"
                class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
              >
                <option value="manual" selected={@campaign.trigger == "manual"}>Manual</option>
                <option value="source" selected={@campaign.trigger == "source"}>Source</option>
                <option value="scheduled" selected={@campaign.trigger == "scheduled"}>
                  Scheduled
                </option>
              </select>
            </div>
            <%= if @trigger_preview == "scheduled" do %>
              <% {interval, unit} = parse_schedule(@campaign.schedule) %>
              <.schedule_picker namespace="campaign" unit={unit} interval={interval} id_prefix={"campaign-#{@campaign.id}"} />
            <% end %>
            <%= if @trigger_preview == "source" do %>
              <.source_picker sources={@sources} namespace="campaign" selected_ids={@campaign.source_ids} />
            <% end %>
            <div class="flex justify-end pt-1">
              <.button type="submit" size="sm" variant="outline">Save changes</.button>
            </div>
          </form>
          <div class="space-y-1.5 mt-4">
            <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Quests (in order)
            </p>
            <%= if @campaign.steps == [] do %>
              <p class="text-sm text-muted-foreground italic">No quests added yet.</p>
            <% else %>
              <div class="rounded-md border divide-y divide-border">
                <%= for {step, idx} <- Enum.with_index(@campaign.steps) do %>
                  <div class="flex items-center gap-2 text-sm px-3 py-2 bg-card hover:bg-muted/30">
                    <span class="text-muted-foreground text-xs w-5 shrink-0 text-center select-none">
                      {idx + 1}
                    </span>
                    <span class="flex-1 truncate font-medium">
                      {quest_name_for_step(step, @quests)}
                    </span>
                    <div class="flex items-center gap-1 shrink-0">
                      <button
                        type="button"
                        class="inline-flex items-center justify-center h-7 w-7 rounded border text-xs font-bold transition-colors disabled:opacity-20 disabled:cursor-not-allowed disabled:pointer-events-none border-border text-muted-foreground hover:bg-muted hover:text-foreground"
                        phx-click="move_campaign_quest_up"
                        phx-value-campaign_id={@campaign.id}
                        phx-value-index={idx}
                        disabled={idx == 0}
                        aria-label="Move up"
                      >▲</button>
                      <button
                        type="button"
                        class="inline-flex items-center justify-center h-7 w-7 rounded border text-xs font-bold transition-colors disabled:opacity-20 disabled:cursor-not-allowed disabled:pointer-events-none border-border text-muted-foreground hover:bg-muted hover:text-foreground"
                        phx-click="move_campaign_quest_down"
                        phx-value-campaign_id={@campaign.id}
                        phx-value-index={idx}
                        disabled={idx == length(@campaign.steps) - 1}
                        aria-label="Move down"
                      >▼</button>
                      <button
                        type="button"
                        class="inline-flex items-center justify-center h-7 w-7 rounded border text-xs transition-colors border-border text-muted-foreground hover:bg-destructive/10 hover:text-destructive hover:border-destructive/30"
                        phx-click="remove_campaign_quest"
                        phx-value-campaign_id={@campaign.id}
                        phx-value-index={idx}
                        aria-label="Remove"
                      >✕</button>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
            <form phx-submit="add_campaign_quest" class="flex gap-2 mt-2">
              <input type="hidden" name="campaign_id" value={@campaign.id} />
              <select
                name="quest_id"
                class="flex-1 text-sm border border-input rounded-md px-2 py-1 bg-background"
              >
                <option value="">Add quest…</option>
                <%= for quest <- @quests do %>
                  <option value={quest.id}>{quest.name}</option>
                <% end %>
              </select>
              <.button type="submit" size="sm" variant="outline">Add</.button>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :run_state, :map, required: true

  defp run_result(assigns) do
    ~H"""
    <div class={["rounded p-3 text-sm space-y-2", run_state_class(@run_state.status)]}>
      <div class="font-medium">{String.capitalize(@run_state.status)}</div>
      <%= if result = @run_state.result do %>
        <%= if is_map(result) and Map.has_key?(result, :verdict) do %>
          <div class="flex items-center gap-2">
            <span class="text-xs font-semibold uppercase">Overall:</span>
            <.verdict_badge verdict={result.verdict} />
          </div>
          <%= for {step, idx} <- Enum.with_index(result.steps || []) do %>
            <div class="border-l-2 border-current pl-2 opacity-80">
              <div class="flex items-center gap-2 text-xs">
                <span class="font-medium">Step {idx + 1}</span>
                <span class="opacity-60">{step.who} · {step.how}</span>
                <.verdict_badge verdict={step.verdict} />
              </div>
              <%= for r <- step.results || [] do %>
                <div class="text-xs opacity-70 mt-0.5 ml-2">
                  <span class="font-medium">{r.member}:</span>
                  {r.verdict}
                  <%= if r.reason && r.reason != "" do %>
                    — {String.slice(r.reason, 0, 120)}{if String.length(r.reason) > 120, do: "…"}
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        <% else %>
          <pre class="text-xs overflow-auto">{inspect(result, pretty: true)}</pre>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :run, :map, required: true

  defp past_run_row(assigns) do
    results = assigns.run.results || %{}
    verdict = results[:verdict] || results["verdict"]
    assigns = assign(assigns, verdict: verdict)

    ~H"""
    <div class="flex items-start gap-3 text-xs py-2 border-t border-border/50">
      <span class="text-muted-foreground whitespace-nowrap mt-0.5">
        {Calendar.strftime(@run.inserted_at, "%b %d %H:%M")}
      </span>
      <span class="flex-1 text-muted-foreground truncate">
        {if @run.input && @run.input != "", do: @run.input, else: "(scheduled)"}
      </span>
      <div class="flex items-center gap-1.5 shrink-0">
        <span class={[
          "px-1.5 py-0.5 rounded text-xs font-medium",
          case @run.status do
            "complete" -> "bg-green-100 text-green-700"
            "failed" -> "bg-red-100 text-red-700"
            "running" -> "bg-blue-100 text-blue-700"
            _ -> "bg-muted text-muted-foreground"
          end
        ]}>
          {@run.status}
        </span>
        <%= if @verdict do %>
          <.verdict_badge verdict={@verdict} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :verdict, :string, required: true

  defp verdict_badge(assigns) do
    color =
      case assigns.verdict do
        "pass" -> "bg-green-100 text-green-700"
        "warn" -> "bg-yellow-100 text-yellow-700"
        "fail" -> "bg-red-100 text-red-700"
        _ -> "bg-muted text-muted-foreground"
      end

    assigns = assign(assigns, color: color)

    ~H"""
    <span class={["px-1.5 py-0.5 rounded text-xs font-medium", @color]}>{@verdict}</span>
    """
  end

  attr :quest, :map, required: true
  attr :expanded, :boolean, required: true
  attr :run_state, :map, default: nil
  attr :past_runs, :list, default: []
  attr :teams, :list, default: []
  attr :sources, :list, default: []
  attr :heralds, :list, default: []
  attr :trigger_preview, :string, default: "manual"
  attr :output_preview, :string, default: "verdict"
  attr :context_preview, :string, default: "none"
  attr :write_mode_preview, :string, default: "append"

  defp quest_card(assigns) do
    first_step = List.first(assigns.quest.roster || []) || %{}

    escalate_on_val =
      case first_step["escalate_on"] do
        %{"type" => "verdict", "values" => values} ->
          if "warn" in values, do: "warn_or_fail", else: "fail_only"

        "always" ->
          "always"

        _ ->
          "never"
      end

    {context_type_val, context_content_val} =
      case List.first(assigns.quest.context_providers || []) do
        %{"type" => "static", "content" => c} -> {"static", c}
        %{"type" => type} -> {type, ""}
        _ -> {"", ""}
      end

    assigns =
      assigns
      |> assign(:first_step, first_step)
      |> assign(:escalate_on_val, escalate_on_val)
      |> assign(:context_type_val, context_type_val)
      |> assign(:context_content_val, context_content_val)

    ~H"""
    <div class={["border rounded-lg bg-card shadow-sm", if(@quest.status == "paused", do: "opacity-60")]}>
      <div class="flex items-center gap-3 px-5 py-3.5">
        <div
          class="flex flex-1 items-center gap-3 cursor-pointer min-w-0"
          phx-click="toggle_expand"
          phx-value-id={"quest-#{@quest.id}"}
        >
          <span class={[
            "transition-transform duration-150 text-muted-foreground text-lg leading-none",
            if(@expanded, do: "rotate-90")
          ]}>
            ›
          </span>
          <div class="flex-1 min-w-0">
            <span class="font-medium">{@quest.name}</span>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <.badge variant="outline" class="text-xs">{@quest.trigger}</.badge>
            <%= if roster_summary(@quest) != "" do %>
              <.badge variant="secondary" class="text-xs">{roster_summary(@quest)}</.badge>
            <% end %>
            <%= if @quest.output_type in ~w(slack webhook github_issue github_pr email pagerduty) do %>
              <.badge variant="secondary" class="text-xs shrink-0">📣 {@quest.herald_name || @quest.output_type}</.badge>
            <% end %>
          </div>
        </div>
        <div class="flex items-center gap-1 shrink-0 ml-2">
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
        <div class="border-t grid grid-cols-1 lg:grid-cols-2 divide-y lg:divide-y-0 lg:divide-x">
          <%!-- Setup --%>
          <div class="px-5 py-5 space-y-4">
            <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Setup
            </p>
            <form phx-submit="update_quest" phx-change="preview_quest_trigger" class="space-y-4">
              <input type="hidden" name="quest_id" value={@quest.id} />
              <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <div class="space-y-1.5">
                  <label for={"qname-#{@quest.id}"} class="text-sm font-medium">Name</label>
                  <.input id={"qname-#{@quest.id}"} type="text" name="quest[name]" value={@quest.name} />
                </div>
                <div class="space-y-1.5">
                  <label for={"qdesc-#{@quest.id}"} class="text-sm font-medium">Description</label>
                  <.input
                    id={"qdesc-#{@quest.id}"}
                    type="text"
                    name="quest[description]"
                    value={@quest.description || ""}
                    placeholder="Optional"
                  />
                </div>
              </div>
              <div class="space-y-1.5">
                <label for={"qtrigger-#{@quest.id}"} class="text-sm font-medium">Trigger</label>
                <select
                  id={"qtrigger-#{@quest.id}"}
                  name="quest[trigger]"
                  class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                >
                  <option value="manual" selected={@quest.trigger == "manual"}>Manual</option>
                  <option value="source" selected={@quest.trigger == "source"}>Source</option>
                  <option value="scheduled" selected={@quest.trigger == "scheduled"}>
                    Scheduled
                  </option>
                </select>
              </div>
              <%= if @trigger_preview == "scheduled" do %>
                <% {interval, unit} = parse_schedule(@quest.schedule) %>
                <.schedule_picker namespace="quest" unit={unit} interval={interval} id_prefix={"quest-#{@quest.id}"} />
              <% end %>
              <%= if @trigger_preview == "source" do %>
                <.source_picker sources={@sources} namespace="quest" selected_ids={@quest.source_ids} />
              <% end %>
              <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
                <div class="space-y-1.5">
                  <label for={"qwho-#{@quest.id}"} class="text-sm font-medium">Who</label>
                  <select
                    id={"qwho-#{@quest.id}"}
                    name="quest[who]"
                    class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                  >
                    <option value="all" selected={@first_step["who"] == "all"}>Everyone</option>
                    <option value="apprentice" selected={@first_step["who"] == "apprentice"}>
                      Apprentice
                    </option>
                    <option value="journeyman" selected={@first_step["who"] == "journeyman"}>
                      Journeyman
                    </option>
                    <option value="master" selected={@first_step["who"] == "master"}>
                      Master
                    </option>
                    <optgroup label="Cloud">
                      <option
                        value="claude_haiku"
                        selected={@first_step["who"] == "claude_haiku"}
                      >
                        Claude Haiku
                      </option>
                      <option
                        value="claude_sonnet"
                        selected={@first_step["who"] == "claude_sonnet"}
                      >
                        Claude Sonnet
                      </option>
                    </optgroup>
                    <%= if @teams != [] do %>
                      <optgroup label="Teams">
                        <%= for team <- @teams do %>
                          <option
                            value={"team:#{team}"}
                            selected={@first_step["who"] == "team:#{team}"}
                          >
                            {team}
                          </option>
                        <% end %>
                      </optgroup>
                    <% end %>
                  </select>
                </div>
                <div class="space-y-1.5">
                  <label for={"qhow-#{@quest.id}"} class="text-sm font-medium">How</label>
                  <select
                    id={"qhow-#{@quest.id}"}
                    name="quest[how]"
                    class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                  >
                    <option value="consensus" selected={@first_step["how"] == "consensus"}>
                      Consensus
                    </option>
                    <option value="solo" selected={@first_step["how"] == "solo"}>Solo</option>
                    <option value="majority" selected={@first_step["how"] == "majority"}>
                      Majority
                    </option>
                  </select>
                </div>
                <%= if @output_preview == "verdict" do %>
                  <div class="space-y-1.5">
                    <label for={"qescalate-#{@quest.id}"} class="text-sm font-medium">
                      Escalate on
                    </label>
                    <select
                      id={"qescalate-#{@quest.id}"}
                      name="quest[escalate_on]"
                      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                    >
                      <option value="never" selected={@escalate_on_val == "never"}>Never</option>
                      <option value="warn_or_fail" selected={@escalate_on_val == "warn_or_fail"}>
                        Warn or fail
                      </option>
                      <option value="fail_only" selected={@escalate_on_val == "fail_only"}>
                        Fail only
                      </option>
                      <option value="always" selected={@escalate_on_val == "always"}>Always</option>
                    </select>
                  </div>
                <% end %>
              </div>
              <div class="space-y-1.5">
                <label for={"qctx-#{@quest.id}"} class="text-sm font-medium">Context</label>
                <select
                  id={"qctx-#{@quest.id}"}
                  name="quest[context_type]"
                  class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                >
                  <option value="" selected={@context_type_val == ""}>None</option>
                  <option value="static" selected={@context_type_val == "static"}>
                    Static text
                  </option>
                  <option value="quest_history" selected={@context_type_val == "quest_history"}>
                    Quest history
                  </option>
                  <option value="member_stats" selected={@context_type_val == "member_stats"}>
                    Member roster
                  </option>
                  <option value="lore" selected={@context_type_val == "lore"}>
                    Knowledge board
                  </option>
                </select>
                <%= if @context_type_val == "static" do %>
                  <.input
                    type="textarea"
                    name="quest[context_content]"
                    value={@context_content_val}
                    rows={2}
                    placeholder="Static context text"
                  />
                <% end %>
                <%= if @context_preview == "lore" do %>
                  <% lore_provider = List.first(Enum.filter(@quest.context_providers || [], &(&1["type"] == "lore"))) || %{} %>
                  <div class="grid grid-cols-3 gap-2 mt-1">
                    <div>
                      <label class="text-xs text-muted-foreground">Tags (comma-sep)</label>
                      <input
                        type="text"
                        name="quest[kb_tags]"
                        value={Enum.join(lore_provider["tags"] || [], ", ")}
                        placeholder="a11y, security"
                        class="w-full h-8 text-sm border border-input rounded-md px-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                      />
                    </div>
                    <div>
                      <label class="text-xs text-muted-foreground">Limit</label>
                      <input
                        type="number"
                        name="quest[kb_limit]"
                        value={lore_provider["limit"] || 10}
                        min="1"
                        class="w-full h-8 text-sm border border-input rounded-md px-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                      />
                    </div>
                    <div>
                      <label class="text-xs text-muted-foreground">Sort</label>
                      <select
                        name="quest[kb_sort]"
                        class="w-full h-8 text-sm border border-input rounded-md px-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                      >
                        <option value="newest" selected={lore_provider["sort"] == "newest"}>
                          Newest
                        </option>
                        <option value="importance" selected={lore_provider["sort"] == "importance"}>
                          Importance
                        </option>
                      </select>
                    </div>
                  </div>
                <% end %>
              </div>
              <div class="space-y-1.5">
                <label for={"qoutput-#{@quest.id}"} class="text-sm font-medium">Output</label>
                <select
                  id={"qoutput-#{@quest.id}"}
                  name="quest[output_type]"
                  class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                >
                  <option value="verdict" selected={@output_preview == "verdict"}>
                    Verdict (pass/warn/fail)
                  </option>
                  <option value="artifact" selected={@output_preview == "artifact"}>
                    Artifact (write to Grimoire)
                  </option>
                  <optgroup label="Heralds">
                    <option value="slack" selected={@output_preview == "slack"}>Slack</option>
                    <option value="webhook" selected={@output_preview == "webhook"}>Webhook</option>
                    <option value="github_issue" selected={@output_preview == "github_issue"}>GitHub Issue</option>
                    <option value="github_pr" selected={@output_preview == "github_pr"}>GitHub PR</option>
                    <option value="email" selected={@output_preview == "email"}>Email</option>
                    <option value="pagerduty" selected={@output_preview == "pagerduty"}>PagerDuty</option>
                  </optgroup>
                </select>
              </div>
              <%= if @output_preview == "artifact" do %>
                <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <div class="space-y-1.5">
                    <label for={"qwritemode-#{@quest.id}"} class="text-sm font-medium">
                      Write mode
                    </label>
                    <select
                      id={"qwritemode-#{@quest.id}"}
                      name="quest[write_mode]"
                      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                    >
                      <option value="append" selected={@write_mode_preview == "append"}>
                        Append (each run adds an entry)
                      </option>
                      <option value="replace" selected={@write_mode_preview == "replace"}>
                        Replace (overwrite previous entry)
                      </option>
                      <option value="both" selected={@write_mode_preview == "both"}>
                        Both (update summary + append log)
                      </option>
                    </select>
                  </div>
                  <div class="space-y-1.5">
                    <label for={"qtitletempl-#{@quest.id}"} class="text-sm font-medium">
                      Title template
                    </label>
                    <input
                      id={"qtitletempl-#{@quest.id}"}
                      type="text"
                      name="quest[entry_title_template]"
                      value={@quest.entry_title_template || ""}
                      placeholder="Summary — {date}"
                      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                    />
                  </div>
                </div>
                <%= if @write_mode_preview == "both" do %>
                  <div>
                    <label class="text-sm font-medium">Log title template</label>
                    <input
                      type="text"
                      name="quest[log_title_template]"
                      value={@quest.log_title_template || ""}
                      placeholder="Log — {date}"
                      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                    />
                  </div>
                <% end %>
              <% end %>
              <%= if @output_preview in ~w(slack webhook github_issue github_pr email pagerduty) do %>
                <% type_heralds = Enum.filter(@heralds, &(&1.type == @output_preview)) %>
                <div class="space-y-1.5">
                  <label class="text-sm font-medium">Herald</label>
                  <%= if type_heralds == [] do %>
                    <p class="text-xs text-muted-foreground mt-1">
                      No <strong>{@output_preview}</strong> heralds configured.
                      <a href="/library" class="underline">Add one in Library → Heralds.</a>
                    </p>
                  <% else %>
                    <select
                      name="quest[herald_name]"
                      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                    >
                      <%= for h <- type_heralds do %>
                        <option value={h.name} selected={@quest.herald_name == h.name}>{h.name}</option>
                      <% end %>
                    </select>
                  <% end %>
                </div>
              <% end %>
              <div class="flex justify-end pt-1">
                <.button type="submit" size="sm" variant="outline">Save changes</.button>
              </div>
            </form>
          </div>
          <%!-- Run --%>
          <div class="px-5 py-5 space-y-4">
            <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Run</p>
            <form id={"run-form-#{@quest.id}"} phx-submit="run_quest" class="space-y-2">
              <input type="hidden" name="quest_id" value={@quest.id} />
              <.input
                type="textarea"
                name="input"
                value=""
                rows={4}
                placeholder="Paste content to evaluate…"
              />
              <div class="flex justify-end">
                <.button type="submit" size="sm">Run Now</.button>
              </div>
            </form>
            <%= if @run_state do %>
              <.run_result run_state={@run_state} />
            <% end %>
            <%= if @past_runs != [] do %>
              <div class="space-y-0 pt-2">
                <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
                  Log
                </p>
                <%= for run <- @past_runs do %>
                  <.past_run_row run={run} />
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp rebuild_trigger_previews(quests, campaigns, existing) do
    existing
    |> Map.merge(Map.new(quests, fn q -> {"quest-#{q.id}", q.trigger} end))
    |> Map.merge(Map.new(campaigns, fn c -> {"campaign-#{c.id}", c.trigger} end))
  end

  defp rebuild_output_previews(quests, existing) do
    Map.merge(existing, Map.new(quests, fn q -> {"quest-#{q.id}", q.output_type || "verdict"} end))
  end

  defp rebuild_write_mode_previews(quests, existing) do
    Map.merge(existing, Map.new(quests, fn q -> {"quest-#{q.id}", q.write_mode || "append"} end))
  end

  defp rebuild_context_previews(quests, existing) do
    Map.merge(
      existing,
      Map.new(quests, fn q ->
        type =
          case q.context_providers do
            [%{"type" => t} | _] -> t
            _ -> "none"
          end

        {"quest-#{q.id}", type}
      end)
    )
  end

  # "*/5 * * * *" → {5, "minutes"}, "0 */2 * * *" → {2, "hours"}
  defp parse_schedule(nil), do: {1, "hours"}
  defp parse_schedule(""), do: {1, "hours"}

  defp parse_schedule(cron) do
    case String.split(cron) do
      ["*/" <> n, "*", "*", "*", "*"] -> {String.to_integer(n), "minutes"}
      ["*", "*", "*", "*", "*"] -> {1, "minutes"}
      ["0", "*/" <> n, "*", "*", "*"] -> {String.to_integer(n), "hours"}
      ["0", "*", "*", "*", "*"] -> {1, "hours"}
      _ -> {1, "hours"}
    end
  end

  defp build_schedule(interval, "minutes"), do: "*/#{interval} * * * *"
  defp build_schedule(interval, "hours"), do: "0 */#{interval} * * *"
  defp build_schedule(_, _), do: nil

  defp roster_summary(%Quest{roster: []}), do: ""
  defp roster_summary(%Quest{roster: [first | _]}), do: "#{first["who"]} · #{first["how"]}"

  defp list_teams do
    import Ecto.Query

    ExCalibur.Repo.all(
      from m in Member,
        where: m.type == "role" and m.status == "active" and not is_nil(m.team),
        select: m.team,
        distinct: true,
        order_by: m.team
    )
  end

  defp run_state_class("running"), do: "bg-blue-50 text-blue-700 border border-blue-200"
  defp run_state_class("complete"), do: "bg-green-50 text-green-700 border border-green-200"
  defp run_state_class("failed"), do: "bg-red-50 text-red-700 border border-red-200"
  defp run_state_class(_), do: "bg-muted text-muted-foreground"

  defp source_label(%Source{name: name}) when is_binary(name) and name != "", do: name

  defp source_label(%Source{book_id: book_id}) when is_binary(book_id) do
    case Book.get(book_id) do
      nil -> book_id
      book -> book.name
    end
  end

  defp source_label(%Source{source_type: type}), do: String.capitalize(type) <> " source"

  defp quest_name_for_step(step, quests) do
    quest = Enum.find(quests, &(to_string(&1.id) == to_string(step["quest_id"])))
    if quest, do: quest.name, else: "Unknown Quest"
  end
end
