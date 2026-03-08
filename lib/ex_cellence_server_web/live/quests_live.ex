defmodule ExCellenceServerWeb.QuestsLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import SaladUI.Badge

  alias ExCellenceServer.Evaluator
  alias ExCellenceServer.Quests
  alias ExCellenceServer.Quests.Quest

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       quests: Quests.list_quests(),
       campaigns: Quests.list_campaigns(),
       expanded: MapSet.new(),
       adding_quest: false,
       adding_campaign: false,
       running: %{}
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Quests")}
  end

  @impl true
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
  def handle_event("create_quest", %{"quest" => params}, socket) do
    roster = [
      %{
        "who" => params["who"] || "all",
        "when" => "on_trigger",
        "how" => params["how"] || "consensus"
      }
    ]

    attrs = %{
      name: params["name"],
      description: params["description"],
      trigger: params["trigger"] || "manual",
      schedule: params["schedule"],
      roster: roster,
      status: "active"
    }

    case Quests.create_quest(attrs) do
      {:ok, _} ->
        {:noreply, assign(socket, quests: Quests.list_quests(), adding_quest: false)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create quest")}
    end
  end

  @impl true
  def handle_event("create_campaign", %{"campaign" => params}, socket) do
    quest_ids =
      params
      |> Map.get("quest_ids", "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    steps =
      Enum.map(quest_ids, &%{"quest_id" => &1, "flow" => "always"})

    attrs = %{
      name: params["name"],
      description: params["description"],
      trigger: params["trigger"] || "manual",
      steps: steps,
      status: "active"
    }

    case Quests.create_campaign(attrs) do
      {:ok, _} ->
        {:noreply, assign(socket, campaigns: Quests.list_campaigns(), adding_campaign: false)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create campaign")}
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
      result = Evaluator.evaluate(input)
      send(parent, {:quest_run_complete, run_id, quest_run.id, result})
    end)

    {:noreply, assign(socket, running: running)}
  end

  def handle_event("run_quest", _, socket) do
    {:noreply, put_flash(socket, :error, "Please enter some input to evaluate")}
  end

  @impl true
  def handle_info({:quest_run_complete, run_id, quest_run_id, result}, socket) do
    {status, results} =
      case result do
        {:ok, outcome} -> {"complete", outcome}
        {:error, reason} -> {"failed", %{error: inspect(reason)}}
      end

    quest_run = ExCellenceServer.Repo.get!(ExCellenceServer.Quests.QuestRun, quest_run_id)
    Quests.update_quest_run(quest_run, %{status: status, results: results})

    running = Map.put(socket.assigns.running, run_id, %{status: status, result: results})
    {:noreply, assign(socket, running: running)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Quests</h1>
        <div class="flex gap-2">
          <.button variant="outline" size="sm" phx-click="add_campaign">+ New Campaign</.button>
          <.button variant="outline" size="sm" phx-click="add_quest">+ New Quest</.button>
        </div>
      </div>

      <%= if @adding_quest do %>
        <.new_quest_form />
      <% end %>

      <%= if @adding_campaign do %>
        <.new_campaign_form quests={@quests} />
      <% end %>

      <%= if @campaigns != [] do %>
        <div>
          <h2 class="text-sm font-semibold text-muted-foreground uppercase tracking-wide mb-2">
            Campaigns
          </h2>
          <div class="space-y-2">
            <.campaign_card
              :for={campaign <- @campaigns}
              campaign={campaign}
              quests={@quests}
              expanded={MapSet.member?(@expanded, "campaign-#{campaign.id}")}
            />
          </div>
        </div>
      <% end %>

      <div>
        <h2 class="text-sm font-semibold text-muted-foreground uppercase tracking-wide mb-2">
          Quests
        </h2>
        <div class="space-y-2">
          <.quest_card
            :for={quest <- @quests}
            quest={quest}
            expanded={MapSet.member?(@expanded, "quest-#{quest.id}")}
            run_state={Map.get(@running, to_string(quest.id))}
          />
        </div>
      </div>
    </div>
    """
  end

  defp new_quest_form(assigns) do
    ~H"""
    <div class="border rounded-lg border-dashed p-4">
      <form phx-submit="create_quest" class="space-y-3">
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="text-sm font-medium">Name</label>
            <.input type="text" name="quest[name]" value="" placeholder="e.g. WCAG Hourly Scan" />
          </div>
          <div>
            <label class="text-sm font-medium">Description</label>
            <.input type="text" name="quest[description]" value="" placeholder="Optional" />
          </div>
        </div>
        <div class="grid grid-cols-3 gap-3">
          <div>
            <label class="text-sm font-medium">Who runs it</label>
            <select name="quest[who]" class="w-full text-sm border rounded px-2 py-1 bg-background">
              <option value="all">Everyone</option>
              <option value="apprentice">Apprentice tier</option>
              <option value="journeyman">Journeyman tier</option>
              <option value="master">Master tier</option>
            </select>
          </div>
          <div>
            <label class="text-sm font-medium">How</label>
            <select name="quest[how]" class="w-full text-sm border rounded px-2 py-1 bg-background">
              <option value="consensus">Consensus</option>
              <option value="solo">Solo</option>
              <option value="unanimous">Unanimous</option>
              <option value="first_to_pass">First to pass</option>
            </select>
          </div>
          <div>
            <label class="text-sm font-medium">Trigger</label>
            <select
              name="quest[trigger]"
              class="w-full text-sm border rounded px-2 py-1 bg-background"
            >
              <option value="manual">Manual</option>
              <option value="source">Source</option>
              <option value="scheduled">Scheduled</option>
            </select>
          </div>
        </div>
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

  attr :quests, :list, required: true

  defp new_campaign_form(assigns) do
    ~H"""
    <div class="border rounded-lg border-dashed p-4">
      <form phx-submit="create_campaign" class="space-y-3">
        <div class="grid grid-cols-2 gap-3">
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
          <label class="text-sm font-medium">Quests (select in order)</label>
          <select
            name="campaign[quest_ids]"
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
  attr :expanded, :boolean, required: true

  defp campaign_card(assigns) do
    ~H"""
    <div class={["border rounded-lg bg-card", if(@campaign.status == "paused", do: "opacity-60")]}>
      <div class="flex items-center gap-3 px-4 py-3">
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
        <div class="border-t px-4 py-3 space-y-2">
          <%= if @campaign.description do %>
            <p class="text-sm text-muted-foreground">{@campaign.description}</p>
          <% end %>
          <div class="space-y-1">
            <%= for {step, idx} <- Enum.with_index(@campaign.steps) do %>
              <div class="flex items-center gap-2 text-sm">
                <span class="text-muted-foreground">{idx + 1}.</span>
                <span>{quest_name_for_step(step, @quests)}</span>
                <%= if idx < length(@campaign.steps) - 1 do %>
                  <.badge variant="secondary" class="text-xs">{step["flow"]}</.badge>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :quest, :map, required: true
  attr :expanded, :boolean, required: true
  attr :run_state, :map, default: nil

  defp quest_card(assigns) do
    ~H"""
    <div class={["border rounded-lg bg-card", if(@quest.status == "paused", do: "opacity-60")]}>
      <div class="flex items-center gap-3 px-4 py-3">
        <div
          class="flex flex-1 items-center gap-3 cursor-pointer min-w-0"
          phx-click="toggle_expand"
          phx-value-id={"quest-#{@quest.id}"}
        >
          <span class={[
            "transition-transform text-muted-foreground",
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
          </div>
        </div>
        <div class="flex items-center gap-2 shrink-0">
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
        <div class="border-t px-4 py-4 space-y-3">
          <%= if @quest.description do %>
            <p class="text-sm text-muted-foreground">{@quest.description}</p>
          <% end %>
          <form phx-submit="run_quest" class="flex gap-2">
            <input type="hidden" name="quest_id" value={@quest.id} />
            <.input
              type="textarea"
              name="input"
              value=""
              rows={3}
              placeholder="Paste content to evaluate..."
              class="flex-1 text-sm"
            />
            <div class="flex flex-col justify-end">
              <.button type="submit" size="sm">Run Now</.button>
            </div>
          </form>
          <%= if @run_state do %>
            <div class={["rounded p-3 text-sm", run_state_class(@run_state.status)]}>
              <span class="font-medium">{String.capitalize(@run_state.status)}</span>
              <%= if @run_state.result do %>
                <pre class="mt-1 text-xs overflow-auto">{inspect(@run_state.result, pretty: true)}</pre>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp roster_summary(%Quest{roster: []}), do: ""
  defp roster_summary(%Quest{roster: [first | _]}), do: "#{first["who"]} · #{first["how"]}"

  defp run_state_class("running"), do: "bg-blue-50 text-blue-700 border border-blue-200"
  defp run_state_class("complete"), do: "bg-green-50 text-green-700 border border-green-200"
  defp run_state_class("failed"), do: "bg-red-50 text-red-700 border border-red-200"
  defp run_state_class(_), do: "bg-muted text-muted-foreground"

  defp quest_name_for_step(step, quests) do
    quest = Enum.find(quests, &(to_string(&1.id) == to_string(step["quest_id"])))
    if quest, do: quest.name, else: "Unknown Quest"
  end
end
