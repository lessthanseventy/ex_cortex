defmodule ExCalibur.ScheduledQuestRunner do
  @moduledoc """
  GenServer that wakes up every minute and runs any scheduled campaigns whose
  cron expression matches the current time.

  Campaigns with `trigger: "scheduled"` and a valid `schedule` cron string
  (e.g. "*/15 * * * *") will be run with an empty input string.
  Wrap a single quest in a one-step campaign to schedule it.
  """

  use GenServer

  alias ExCalibur.CampaignRunner
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
    run_due_campaigns()
    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  defp run_due_campaigns do
    now = DateTime.utc_now()

    Quests.list_campaigns()
    |> Enum.filter(&campaign_scheduled_and_due?(&1, now))
    |> Enum.each(&run_campaign/1)
  end

  defp campaign_scheduled_and_due?(campaign, now) do
    campaign.trigger == "scheduled" and
      campaign.status == "active" and
      is_binary(campaign.schedule) and
      campaign.schedule != "" and
      cron_matches?(campaign.schedule, now)
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

  defp run_campaign(campaign) do
    Logger.info("[ScheduledQuestRunner] Running campaign #{campaign.id} (#{campaign.name})")

    Task.start(fn ->
      {:ok, result} = CampaignRunner.run(campaign, "")
      Logger.info("[ScheduledQuestRunner] Campaign #{campaign.id} complete: #{inspect(result)}")
    end)
  end
end
