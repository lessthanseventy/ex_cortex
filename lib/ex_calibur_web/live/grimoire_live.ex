defmodule ExCaliburWeb.GrimoireLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import Ecto.Query
  import SaladUI.Badge
  import SaladUI.Card
  import SaladUI.Tabs

  alias ExCalibur.Lodge.Card
  alias ExCalibur.Lore
  alias ExCalibur.Lore.LoreEntry
  alias ExCalibur.Quests
  alias ExCalibur.Quests.Quest
  alias ExCalibur.Quests.QuestRun
  alias ExCalibur.Repo
  alias ExCalibur.Settings
  alias ExCalibur.Sources.Source

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
    telemetry = load_telemetry(quests, run_stats)

    {:ok,
     assign(socket,
       page_title: "Grimoire",
       active_tab: "quest-log",
       quests: quests,
       run_stats: run_stats,
       telemetry: telemetry,
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
      |> Map.new(fn {quest_id, quest_runs} -> {quest_id, build_quest_stats(quest_runs)} end)
    end
  end

  defp build_quest_stats(quest_runs) do
    total = length(quest_runs)
    complete = Enum.count(quest_runs, fn {_, status, _} -> status == "complete" end)
    failed = Enum.count(quest_runs, fn {_, status, _} -> status == "failed" end)

    last_run =
      quest_runs
      |> Enum.map(&elem(&1, 2))
      |> Enum.max(NaiveDateTime, fn -> nil end)

    %{total: total, complete: complete, failed: failed, last_run: last_run}
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
          <p class="text-sm text-muted-foreground">
            {length(@quests)} quests tracked · {Enum.sum(
              Enum.map(@run_stats, fn {_id, s} -> s.total end)
            )} runs total
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
                    page. Once quests run, their history and lore entries show up here.
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
              <%!-- Overview Stats --%>
              <div class="grid gap-4 grid-cols-2 md:grid-cols-4">
                <.card>
                  <.card_content class="pt-6">
                    <div class="text-2xl font-bold">{@telemetry.uptime}</div>
                    <p class="text-xs text-muted-foreground">Uptime</p>
                  </.card_content>
                </.card>
                <.card>
                  <.card_content class="pt-6">
                    <div class="text-2xl font-bold">{@telemetry.total_runs}</div>
                    <p class="text-xs text-muted-foreground">Quest Runs</p>
                  </.card_content>
                </.card>
                <.card>
                  <.card_content class="pt-6">
                    <div class="text-2xl font-bold">{@telemetry.lore_count}</div>
                    <p class="text-xs text-muted-foreground">Lore Entries</p>
                  </.card_content>
                </.card>
                <.card>
                  <.card_content class="pt-6">
                    <div class="text-2xl font-bold">{@telemetry.card_count}</div>
                    <p class="text-xs text-muted-foreground">Lodge Cards</p>
                  </.card_content>
                </.card>
              </div>

              <%!-- Sources --%>
              <.card>
                <.card_header>
                  <.card_title>Sources</.card_title>
                  <.card_description>
                    Data sources feeding your guilds.
                  </.card_description>
                </.card_header>
                <.card_content>
                  <div class="flex items-center gap-4 text-sm">
                    <div>
                      <span class="text-2xl font-bold">{@telemetry.sources.total}</span>
                      <span class="text-muted-foreground ml-1">total</span>
                    </div>
                    <div class="flex items-center gap-1.5">
                      <span class="h-2 w-2 rounded-full bg-green-500"></span>
                      <span>{@telemetry.sources.active} active</span>
                    </div>
                    <%= if @telemetry.sources.paused > 0 do %>
                      <div class="flex items-center gap-1.5">
                        <span class="h-2 w-2 rounded-full bg-yellow-500"></span>
                        <span>{@telemetry.sources.paused} paused</span>
                      </div>
                    <% end %>
                    <%= if @telemetry.sources.error > 0 do %>
                      <div class="flex items-center gap-1.5">
                        <span class="h-2 w-2 rounded-full bg-red-500"></span>
                        <span class="text-destructive">{@telemetry.sources.error} errored</span>
                      </div>
                    <% end %>
                  </div>
                </.card_content>
              </.card>

              <%!-- Ollama --%>
              <.card>
                <.card_header>
                  <.card_title>Ollama</.card_title>
                  <.card_description>
                    LLM backend at {@telemetry.ollama.url}
                  </.card_description>
                </.card_header>
                <.card_content>
                  <div class="flex items-center gap-2 text-sm">
                    <%= if @telemetry.ollama.reachable do %>
                      <span class="h-2 w-2 rounded-full bg-green-500"></span>
                      <span>Reachable — {length(@telemetry.ollama.models)} models loaded</span>
                    <% else %>
                      <span class="h-2 w-2 rounded-full bg-red-500"></span>
                      <span class="text-destructive">Unreachable</span>
                    <% end %>
                  </div>
                  <%= if @telemetry.ollama.reachable and @telemetry.ollama.models != [] do %>
                    <div class="flex flex-wrap gap-1.5 mt-3">
                      <%= for model <- @telemetry.ollama.models do %>
                        <.badge variant="secondary">{model}</.badge>
                      <% end %>
                    </div>
                  <% end %>
                </.card_content>
              </.card>

              <%!-- Dev Team Pipeline --%>
              <%= if @telemetry.dev_team != [] do %>
                <.card>
                  <.card_header>
                    <.card_title>Self-Improvement Pipeline</.card_title>
                    <.card_description>
                      Dev Team quest status — last run and artifacts produced.
                    </.card_description>
                  </.card_header>
                  <.card_content>
                    <div class="space-y-2">
                      <%= for entry <- @telemetry.dev_team do %>
                        <div class="flex items-start gap-3 text-sm py-1 border-b last:border-0">
                          <div class="flex-1 min-w-0">
                            <div class="flex items-center gap-2">
                              <span class="font-medium truncate">{entry.quest.name}</span>
                              <%= if entry.last_run do %>
                                <.badge
                                  variant={run_status_variant(entry.last_run.status)}
                                  class="text-xs"
                                >
                                  {entry.last_run.status}
                                </.badge>
                              <% end %>
                            </div>
                            <%= if entry.last_run do %>
                              <div class="text-xs text-muted-foreground mt-0.5 flex items-center gap-2">
                                <span>{format_time(entry.last_run.inserted_at)}</span>
                                <%= if entry.tool_call_count > 0 do %>
                                  <span>
                                    · {entry.tool_call_count} tool call{if entry.tool_call_count != 1,
                                      do: "s"}
                                  </span>
                                <% end %>
                              </div>
                              <%= if entry.artifacts != [] do %>
                                <div class="flex flex-wrap gap-1 mt-1">
                                  <%= for url <- Enum.uniq(entry.artifacts) do %>
                                    <a
                                      href={url}
                                      target="_blank"
                                      class="text-xs text-primary underline underline-offset-2"
                                    >
                                      {url |> String.split("/") |> Enum.take(-2) |> Enum.join("/")}
                                    </a>
                                  <% end %>
                                </div>
                              <% end %>
                            <% else %>
                              <div class="text-xs text-muted-foreground mt-0.5">Never run</div>
                            <% end %>
                          </div>
                          <.badge variant="outline" class="text-xs shrink-0">
                            {entry.quest.trigger}
                          </.badge>
                        </div>
                      <% end %>
                    </div>
                  </.card_content>
                </.card>
              <% end %>

              <%!-- CLI Tools --%>
              <.card>
                <.card_header>
                  <.card_title>CLI Tools</.card_title>
                  <.card_description>
                    External binaries used by tools and sources — checked at startup.
                  </.card_description>
                </.card_header>
                <.card_content>
                  <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2">
                    <%= for tool <- @telemetry.cli_tools.available do %>
                      <div class="flex items-center gap-2 rounded-md border px-3 py-2 text-sm">
                        <span class="h-2 w-2 rounded-full bg-green-500 shrink-0"></span>
                        <span class="truncate">{tool}</span>
                      </div>
                    <% end %>
                    <%= for tool <- @telemetry.cli_tools.missing do %>
                      <div class="flex items-center gap-2 rounded-md border border-dashed px-3 py-2 text-sm text-muted-foreground">
                        <span class="h-2 w-2 rounded-full bg-muted shrink-0"></span>
                        <span class="truncate">{tool}</span>
                      </div>
                    <% end %>
                  </div>
                  <p class="text-xs text-muted-foreground mt-3">
                    {length(@telemetry.cli_tools.available)} available · {length(
                      @telemetry.cli_tools.missing
                    )} missing
                  </p>
                </.card_content>
              </.card>
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
            <p class="text-sm text-muted-foreground">
              No runs yet. Run this quest from the
              <a href="/quests" class="underline text-primary">Quests</a>
              page, or set a trigger to run it automatically.
            </p>
          <% else %>
            <div class="space-y-3">
              <%= for run <- @runs do %>
                <% all_tool_calls =
                  run.step_results |> Map.values() |> Enum.flat_map(&Map.get(&1, "tool_calls", [])) %>
                <% artifacts =
                  all_tool_calls
                  |> Enum.flat_map(fn call ->
                    Regex.scan(~r{https://github\.com/\S+}, call["output"] || "")
                    |> List.flatten()
                  end) %>
                <div class="rounded-md border p-3 space-y-2">
                  <div class="flex items-center gap-3 text-sm">
                    <.badge variant={run_status_variant(run.status)}>
                      {run.status}
                    </.badge>
                    <span class="text-muted-foreground">{format_time(run.inserted_at)}</span>
                    <%= if all_tool_calls != [] do %>
                      <span class="text-xs text-muted-foreground/60">
                        {length(all_tool_calls)} tool call{if length(all_tool_calls) != 1,
                          do: "s"}
                      </span>
                    <% end %>
                  </div>
                  <%= if all_tool_calls != [] do %>
                    <div class="space-y-1 border-l-2 border-muted pl-3">
                      <%= for call <- all_tool_calls do %>
                        <div class="text-xs space-y-0.5">
                          <span class="font-mono text-accent-foreground">{call["tool"]}</span>
                          <%= if call["output"] && call["output"] != "" do %>
                            <div class="text-muted-foreground/70 break-words">
                              {call["output"]}
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                  <%= if artifacts != [] do %>
                    <div class="flex flex-wrap gap-1.5">
                      <%= for url <- Enum.uniq(artifacts) do %>
                        <a
                          href={url}
                          target="_blank"
                          class="inline-flex items-center gap-1 text-xs rounded-full border px-2 py-0.5 text-primary hover:bg-muted transition-colors"
                        >
                          ↗ {url |> String.split("/") |> Enum.take(-2) |> Enum.join("/")}
                        </a>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
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
            <p class="text-sm text-muted-foreground">
              No lore entries yet. Lore is written by quest steps as they process input.
            </p>
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

  defp load_telemetry(_quests, run_stats) do
    total_runs = run_stats |> Map.values() |> Enum.sum_by(& &1.total)
    lore_count = Repo.aggregate(LoreEntry, :count)
    card_count = Repo.aggregate(Card, :count)

    source_counts =
      from(s in Source, group_by: s.status, select: {s.status, count(s.id)})
      |> Repo.all()
      |> Map.new()

    sources = %{
      total: Enum.sum(Map.values(source_counts)),
      active: Map.get(source_counts, "active", 0),
      paused: Map.get(source_counts, "paused", 0),
      error: Map.get(source_counts, "error", 0)
    }

    ollama = ExCalibur.OllamaCache.get_status()

    cli_tools =
      try do
        :persistent_term.get(:cli_tool_status)
      rescue
        ArgumentError -> %{available: [], missing: []}
      end

    %{
      uptime: format_uptime(),
      total_runs: total_runs,
      lore_count: lore_count,
      card_count: card_count,
      sources: sources,
      ollama: ollama,
      cli_tools: cli_tools,
      dev_team: load_dev_team_status()
    }
  end

  @dev_team_quest_names ~w(Daily Dev Triage Analyze Usage Implement Issue Review PR QA Check UX Review Merge Decision)

  defp load_dev_team_status do
    quests =
      Repo.all(from q in Quest, where: q.name in @dev_team_quest_names, order_by: q.name)

    quest_ids = Enum.map(quests, & &1.id)

    last_runs =
      from(r in QuestRun,
        where: r.quest_id in ^quest_ids,
        order_by: [desc: r.inserted_at]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.quest_id)
      |> Map.new(fn {id, [latest | _]} -> {id, latest} end)

    Enum.map(quests, fn q ->
      run = Map.get(last_runs, q.id)

      tool_calls =
        if run do
          run.step_results
          |> Map.values()
          |> Enum.flat_map(&Map.get(&1, "tool_calls", []))
        else
          []
        end

      artifacts =
        Enum.flat_map(tool_calls, fn call ->
          output = call["output"] || ""
          ~r{https://github\.com/\S+} |> Regex.scan(output) |> List.flatten()
        end)

      %{quest: q, last_run: run, tool_call_count: length(tool_calls), artifacts: artifacts}
    end)
  end

  defp format_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    total_seconds = div(uptime_ms, 1000)
    days = div(total_seconds, 86_400)
    hours = div(rem(total_seconds, 86_400), 3600)
    minutes = div(rem(total_seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h"
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m"
    end
  end

  defp run_status_variant("complete"), do: "default"
  defp run_status_variant("failed"), do: "destructive"
  defp run_status_variant("running"), do: "outline"
  defp run_status_variant(_), do: "secondary"
end
