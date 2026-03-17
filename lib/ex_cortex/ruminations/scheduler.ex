defmodule ExCortex.Ruminations.Scheduler do
  @moduledoc """
  GenServer that wakes up every minute and runs any scheduled ruminations whose
  cron expression matches the current time.

  Ruminations with `trigger: "scheduled"` and a valid `schedule` cron string
  (e.g. "*/15 * * * *") will be run with an empty input string.
  Wrap a single step in a one-step rumination to schedule it.
  """

  use GenServer

  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Runner
  alias ExCortex.Senses.Sense

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
    run_due_ruminations()
    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  defp run_due_ruminations do
    now = DateTime.utc_now()

    Ruminations.list_ruminations()
    |> Enum.filter(&rumination_scheduled_and_due?(&1, now))
    |> Enum.each(&run_rumination/1)
  end

  defp rumination_scheduled_and_due?(rumination, now) do
    rumination.trigger == "scheduled" and
      rumination.status == "active" and
      is_binary(rumination.schedule) and
      rumination.schedule != "" and
      cron_matches?(rumination.schedule, now)
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

  defp run_rumination(rumination) do
    Logger.info("[ScheduledRuminationRunner] Running rumination #{rumination.id} (#{rumination.name})")

    Task.start(fn ->
      input = gather_source_input(rumination)
      {:ok, result} = Runner.run(rumination, input)
      Logger.info("[ScheduledRuminationRunner] Rumination #{rumination.id} complete: #{inspect(result)}")
    end)
  end

  # If the rumination has source_ids, fetch recent data from those senses
  # and format it as input text. Otherwise return empty string.
  defp gather_source_input(%{source_ids: source_ids}) when is_list(source_ids) and source_ids != [] do
    import Ecto.Query

    senses = ExCortex.Repo.all(from(s in Sense, where: s.id in ^source_ids))

    items =
      Enum.flat_map(senses, fn sense ->
        mod = ExCortex.Senses.Worker.source_module(sense.source_type)
        # Fetch without state tracking — we just want current content
        case mod.fetch(%{last_seen_ids: []}, sense.config) do
          {:ok, items, _state} -> items
          _ -> []
        end
      end)

    if items == [] do
      ""
    else
      header = "## Feed Data: #{length(items)} items from #{length(senses)} source(s)\n\n"

      body =
        items
        |> Enum.take(50)
        |> Enum.with_index(1)
        |> Enum.map_join("\n\n---\n\n", fn {item, idx} ->
          link = get_in(item.metadata, [:link]) || ""
          title = get_in(item.metadata, [:title]) || ""
          link_line = if link == "", do: "", else: "\nURL: #{link}"
          "### Item #{idx}: #{title}#{link_line}\n#{item.content}"
        end)

      header <> body
    end
  end

  defp gather_source_input(_), do: ""
end
