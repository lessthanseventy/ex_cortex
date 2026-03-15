defmodule ExCortex.Thoughts.Scheduler do
  @moduledoc """
  GenServer that wakes up every minute and runs any scheduled thoughts whose
  cron expression matches the current time.

  Thoughts with `trigger: "scheduled"` and a valid `schedule` cron string
  (e.g. "*/15 * * * *") will be run with an empty input string.
  Wrap a single step in a one-step thought to schedule it.
  """

  use GenServer

  alias ExCortex.Thoughts
  alias ExCortex.Thoughts.Runner

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
    run_due_thoughts()
    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  defp run_due_thoughts do
    now = DateTime.utc_now()

    Thoughts.list_thoughts()
    |> Enum.filter(&thought_scheduled_and_due?(&1, now))
    |> Enum.each(&run_thought/1)
  end

  defp thought_scheduled_and_due?(thought, now) do
    thought.trigger == "scheduled" and
      thought.status == "active" and
      is_binary(thought.schedule) and
      thought.schedule != "" and
      cron_matches?(thought.schedule, now)
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

  defp run_thought(thought) do
    Logger.info("[ScheduledThoughtRunner] Running thought #{thought.id} (#{thought.name})")

    Task.start(fn ->
      {:ok, result} = Runner.run(thought, "")
      Logger.info("[ScheduledThoughtRunner] Thought #{thought.id} complete: #{inspect(result)}")
    end)
  end
end
