defmodule ExCaliburWeb.GrimoireLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import Ecto.Query
  import SaladUI.Badge
  import SaladUI.Tabs

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
       run_stats: run_stats
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
    </div>
    """
  end

  attr :quest, :map, required: true
  attr :stats, :map, default: nil

  defp quest_card(assigns) do
    stats = assigns.stats || %{total: 0, complete: 0, failed: 0, last_run: nil}
    assigns = assign(assigns, :stats, stats)

    ~H"""
    <div
      class="rounded-lg border bg-card p-5 space-y-3 hover:border-primary/50 transition-colors"
      data-quest-id={@quest.id}
    >
      <div class="flex items-center justify-between gap-2">
        <span class="font-medium truncate">{@quest.name}</span>
        <.badge variant={if @quest.status == "active", do: "default", else: "secondary"}>
          {@quest.status}
        </.badge>
      </div>
      <%= if @quest.description do %>
        <p class="text-sm text-muted-foreground line-clamp-2">{@quest.description}</p>
      <% end %>
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
      <div class="text-xs text-muted-foreground">
        Last run: {format_time(@stats.last_run)}
      </div>
    </div>
    """
  end
end
