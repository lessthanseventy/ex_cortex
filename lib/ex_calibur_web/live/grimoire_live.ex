defmodule ExCaliburWeb.GrimoireLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import Ecto.Query
  import SaladUI.Badge
  import SaladUI.Card
  import SaladUI.Tabs

  alias ExCalibur.Lore
  alias ExCalibur.Quests
  alias ExCalibur.Quests.QuestRun
  alias ExCalibur.Repo
  alias ExCalibur.Settings

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) and is_nil(Settings.get_banner()) do
      {:ok, push_navigate(socket, to: ~p"/town-square")}
    else
      mount_grimoire(socket)
    end
  end

  defp mount_grimoire(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCalibur.PubSub, "quest_runs")
    end

    quests = Quests.list_quests()
    run_stats = load_run_stats(quests)

    {:ok,
     assign(socket,
       page_title: "Grimoire",
       active_tab: "quest-log",
       quests: quests,
       run_stats: run_stats,
       selected_quest_id: nil,
       selected_quest: nil,
       quest_runs: [],
       quest_lore_entries: []
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:refresh, socket) do
    quests = Quests.list_quests()
    run_stats = load_run_stats(quests)
    {:noreply, assign(socket, quests: quests, run_stats: run_stats)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  def handle_event("select_quest", %{"id" => id}, socket) do
    quest_id = String.to_integer(id)
    {:noreply, load_quest_data(socket, quest_id)}
  end

  def handle_event("back_to_quest_log", _params, socket) do
    {:noreply,
     assign(socket,
       selected_quest_id: nil,
       selected_quest: nil,
       quest_runs: [],
       quest_lore_entries: []
     )}
  end

  defp load_quest_data(socket, quest_id) do
    quest = Quests.get_quest!(quest_id)
    quest_runs = Quests.list_quest_runs(quest)
    lore_entries = Lore.list_entries(quest_id: quest_id)

    assign(socket,
      selected_quest_id: quest_id,
      selected_quest: quest,
      quest_runs: quest_runs,
      quest_lore_entries: lore_entries
    )
  end

  defp load_run_stats(quests) do
    quest_ids = Enum.map(quests, & &1.id)

    if quest_ids == [] do
      %{}
    else
      runs =
        Repo.all(
          from r in QuestRun,
            where: r.quest_id in ^quest_ids,
            select: {r.quest_id, r.status, r.inserted_at}
        )

      runs
      |> Enum.group_by(&elem(&1, 0))
      |> Map.new(fn {quest_id, quest_runs} ->
        total = length(quest_runs)

        complete =
          Enum.count(quest_runs, fn {_, status, _} -> status == "complete" end)

        failed =
          Enum.count(quest_runs, fn {_, status, _} -> status == "failed" end)

        last_run =
          quest_runs
          |> Enum.map(&elem(&1, 2))
          |> Enum.max(NaiveDateTime, fn -> nil end)

        {quest_id, %{total: total, complete: complete, failed: failed, last_run: last_run}}
      end)
    end
  end

  defp format_time(nil), do: "Never"

  defp format_time(dt) do
    Calendar.strftime(dt, "%b %d %H:%M")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if @selected_quest_id do %>
        <.quest_detail
          quest={@selected_quest}
          runs={@quest_runs}
          lore_entries={@quest_lore_entries}
          stats={Map.get(@run_stats, @selected_quest_id)}
        />
      <% else %>
        <div>
          <h1 class="text-3xl font-bold tracking-tight">Grimoire</h1>
          <p class="text-muted-foreground mt-1.5">
            Quest log and telemetry for your guild's missions.
          </p>
        </div>

        <.tabs id="grimoire-tabs" default="quest-log">
          <.tabs_list>
            <.tabs_trigger value="quest-log">Quest Log</.tabs_trigger>
            <.tabs_trigger value="telemetry">Telemetry</.tabs_trigger>
          </.tabs_list>

          <.tabs_content value="quest-log">
            <div class="space-y-4 mt-4">
              <%= if @quests == [] do %>
                <div class="rounded-lg border p-8 text-center">
                  <p class="text-muted-foreground text-sm">
                    No quests yet. Create one from the
                    <a href="/quests" class="underline text-primary">Quests</a>
                    page.
                  </p>
                </div>
              <% else %>
                <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                  <%= for quest <- @quests do %>
                    <.quest_card quest={quest} stats={Map.get(@run_stats, quest.id)} />
                  <% end %>
                </div>
              <% end %>
            </div>
          </.tabs_content>

          <.tabs_content value="telemetry">
            <div class="space-y-4 mt-4">
              <div class="rounded-lg border p-8 text-center">
                <p class="text-muted-foreground text-sm">
                  Telemetry widgets will appear here once monitoring is configured.
                </p>
              </div>
            </div>
          </.tabs_content>
        </.tabs>
      <% end %>
    </div>
    """
  end

  attr :quest, :map, required: true
  attr :stats, :map, default: nil

  defp quest_card(assigns) do
    stats = assigns.stats || %{total: 0, complete: 0, failed: 0, last_run: nil}
    assigns = assign(assigns, :stats, stats)

    ~H"""
    <.card
      class="cursor-pointer hover:border-primary/50 transition-colors"
      phx-click="select_quest"
      phx-value-id={@quest.id}
      data-quest-id={@quest.id}
    >
      <.card_header class="pb-3">
        <div class="flex items-center justify-between gap-2">
          <.card_title class="truncate">{@quest.name}</.card_title>
          <.badge variant={if @quest.status == "active", do: "default", else: "secondary"}>
            {@quest.status}
          </.badge>
        </div>
        <%= if @quest.description do %>
          <.card_description class="line-clamp-2">{@quest.description}</.card_description>
        <% end %>
      </.card_header>
      <.card_content class="pt-0">
        <div class="flex items-center gap-3 text-xs text-muted-foreground">
          <span>Trigger: {@quest.trigger}</span>
          <span>·</span>
          <span>Runs: {@stats.total}</span>
          <%= if @stats.total > 0 do %>
            <span>·</span>
            <span class="text-green-600">{@stats.complete} ok</span>
            <%= if @stats.failed > 0 do %>
              <span class="text-destructive">{@stats.failed} failed</span>
            <% end %>
          <% end %>
        </div>
        <div class="text-xs text-muted-foreground mt-1">
          Last run: {format_time(@stats.last_run)}
        </div>
      </.card_content>
    </.card>
    """
  end

  attr :quest, :map, required: true
  attr :runs, :list, required: true
  attr :lore_entries, :list, required: true
  attr :stats, :map, default: nil

  defp quest_detail(assigns) do
    stats = assigns.stats || %{total: 0, complete: 0, failed: 0, last_run: nil}
    assigns = assign(assigns, :stats, stats)

    ~H"""
    <div class="space-y-6">
      <div class="flex items-center gap-3">
        <.button variant="ghost" size="sm" phx-click="back_to_quest_log">
          &larr; Back to Quest Log
        </.button>
      </div>

      <.card>
        <.card_header>
          <div class="flex items-center justify-between gap-3">
            <.card_title class="text-2xl">{@quest.name}</.card_title>
            <.badge variant={if @quest.status == "active", do: "default", else: "secondary"}>
              {@quest.status}
            </.badge>
          </div>
          <%= if @quest.description do %>
            <.card_description>{@quest.description}</.card_description>
          <% end %>
        </.card_header>
        <.card_content>
          <div class="flex items-center gap-4 text-sm text-muted-foreground">
            <div>
              <span class="font-medium text-foreground">Trigger:</span> {@quest.trigger}
            </div>
            <div>
              <span class="font-medium text-foreground">Total runs:</span> {@stats.total}
            </div>
            <%= if @stats.total > 0 do %>
              <div>
                <span class="text-green-600">{@stats.complete} ok</span>
                <%= if @stats.failed > 0 do %>
                  <span class="text-destructive ml-2">{@stats.failed} failed</span>
                <% end %>
              </div>
            <% end %>
          </div>
        </.card_content>
      </.card>

      <.card>
        <.card_header>
          <.card_title>Run History</.card_title>
          <.card_description>Recent quest runs</.card_description>
        </.card_header>
        <.card_content>
          <%= if @runs == [] do %>
            <p class="text-sm text-muted-foreground">No runs yet.</p>
          <% else %>
            <table class="w-full caption-bottom text-sm" aria-label="Quest run history">
              <thead class="[&_tr]:border-b">
                <tr class="border-b transition-colors">
                  <th class="h-10 px-2 text-left align-middle font-medium text-muted-foreground">
                    Status
                  </th>
                  <th class="h-10 px-2 text-left align-middle font-medium text-muted-foreground">
                    Started
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={run <- @runs} class="border-b transition-colors hover:bg-muted/50">
                  <td class="p-2 align-middle">
                    <.badge variant={run_status_variant(run.status)}>
                      {run.status}
                    </.badge>
                  </td>
                  <td class="p-2 align-middle text-muted-foreground">
                    {format_time(run.inserted_at)}
                  </td>
                </tr>
              </tbody>
            </table>
          <% end %>
        </.card_content>
      </.card>

      <.card>
        <.card_header>
          <.card_title>Lore Entries</.card_title>
          <.card_description>Knowledge generated by this quest</.card_description>
        </.card_header>
        <.card_content>
          <%= if @lore_entries == [] do %>
            <p class="text-sm text-muted-foreground">No lore entries yet.</p>
          <% else %>
            <div class="space-y-3">
              <div :for={entry <- @lore_entries} class="rounded-md border p-3">
                <div class="flex items-center justify-between">
                  <span class="font-medium text-sm">{entry.title}</span>
                  <span class="text-xs text-muted-foreground">
                    {format_time(entry.inserted_at)}
                  </span>
                </div>
                <%= if entry.body && entry.body != "" do %>
                  <p class="text-sm text-muted-foreground mt-1 line-clamp-3">{entry.body}</p>
                <% end %>
              </div>
            </div>
          <% end %>
        </.card_content>
      </.card>
    </div>
    """
  end

  defp run_status_variant("complete"), do: "default"
  defp run_status_variant("failed"), do: "destructive"
  defp run_status_variant("running"), do: "outline"
  defp run_status_variant(_), do: "secondary"
end
