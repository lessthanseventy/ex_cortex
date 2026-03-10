defmodule ExCalibur.ScheduledQuestRunner do
  @moduledoc """
  GenServer that wakes up every minute and runs any scheduled quests whose
  cron expression matches the current time.

  Quests with `trigger: "scheduled"` and a valid `schedule` cron string
  (e.g. "*/15 * * * *") will be run with an empty input string.
  Wrap a single step in a one-step quest to schedule it.
  """

  use GenServer

  alias ExCalibur.QuestRunner
  alias ExCalibur.Quests

  require Logger

  @tick_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    run_due_quests()
    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  defp run_due_quests do
    now = DateTime.utc_now()

    Quests.list_quests()
    |> Enum.filter(&quest_scheduled_and_due?(&1, now))
    |> Enum.each(&run_quest/1)
  end

  defp quest_scheduled_and_due?(quest, now) do
    quest.trigger == "scheduled" and
      quest.status == "active" and
      is_binary(quest.schedule) and
      quest.schedule != "" and
      cron_matches?(quest.schedule, now)
  end

  defp cron_matches?(schedule, now) do
    case Crontab.CronExpression.Parser.parse(schedule) do
      {:ok, expr} ->
        naive = DateTime.to_naive(now)
        Crontab.DateChecker.matches_date?(expr, naive)

      _ ->
        false
    end
  end

  defp run_quest(quest) do
    Logger.info("[ScheduledQuestRunner] Running quest #{quest.id} (#{quest.name})")

    Task.start(fn ->
      {:ok, result} = QuestRunner.run(quest, "")
      Logger.info("[ScheduledQuestRunner] Quest #{quest.id} complete: #{inspect(result)}")
    end)
  end
end
