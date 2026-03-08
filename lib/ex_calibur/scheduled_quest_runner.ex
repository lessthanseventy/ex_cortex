defmodule ExCalibur.ScheduledQuestRunner do
  @moduledoc """
  GenServer that wakes up every minute and runs any scheduled quests whose
  cron expression matches the current time.

  Quests with `trigger: "scheduled"` and a valid `schedule` cron string
  (e.g. "0 * * * *") will be run against an empty input string, which is
  useful for housekeeping quests that synthesize from context providers.
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
    |> Enum.filter(&scheduled_and_due?(&1, now))
    |> Enum.each(&run_quest/1)
  end

  defp scheduled_and_due?(quest, now) do
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

    {:ok, quest_run} =
      Quests.create_quest_run(%{quest_id: quest.id, input: "", status: "running"})

    Task.start(fn ->
      result = QuestRunner.run(quest, "")

      {status, results} =
        case result do
          {:ok, r} -> {"complete", r}
          {:error, e} -> {"failed", %{error: inspect(e)}}
        end

      quest_run_fresh = ExCalibur.Repo.get!(ExCalibur.Quests.QuestRun, quest_run.id)
      Quests.update_quest_run(quest_run_fresh, %{status: status, results: results})

      if status == "complete" do
        ExCalibur.LearningLoop.retrospect(quest, %{quest_run_fresh | results: results})
      end
    end)
  end
end
