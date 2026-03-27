defmodule ExCortex.Senses.Feedback do
  @moduledoc """
  Verdict-driven sense reconfiguration.

  After a daydream completes, analyzes the verdict pattern and adjusts the
  triggering sense's polling interval:

  - Consistently "pass" → lengthen interval (content is routine, check less often)
  - Consistently "fail" → shorten interval (needs more attention)
  - Mixed verdicts → no change

  Subscribes to the "daydreams" PubSub topic and processes completions.
  """

  use GenServer

  import Ecto.Query

  alias ExCortex.Repo
  alias ExCortex.Ruminations.Daydream
  alias ExCortex.Ruminations.Rumination
  alias ExCortex.Senses.Sense

  require Logger

  @min_interval 30_000
  @max_interval 3_600_000
  @speedup_factor 0.75
  @slowdown_factor 1.5
  # Need at least this many recent verdicts to make a decision
  @verdict_window 5

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "daydreams")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:daydream_completed, daydream}, state) do
    Task.start(fn -> process_completion(daydream) end)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp process_completion(daydream) do
    rumination = Repo.get(Rumination, daydream.rumination_id)

    if rumination && rumination.trigger == "source" && rumination.source_ids != [] do
      check_verdict_feedback(rumination)
    end
  rescue
    e -> Logger.debug("[SenseFeedback] Error processing completion: #{Exception.message(e)}")
  end

  defp check_verdict_feedback(rumination) do
    verdicts = recent_verdicts(rumination.id, @verdict_window)

    if length(verdicts) >= @verdict_window do
      adjustment = analyze_verdicts(verdicts)
      if adjustment != :no_change, do: adjust_sources(rumination.source_ids, adjustment)
    end
  end

  defp recent_verdicts(rumination_id, limit) do
    from(d in Daydream,
      where: d.rumination_id == ^rumination_id and d.status == "complete",
      order_by: [desc: d.inserted_at],
      limit: ^limit,
      select: d.synapse_results
    )
    |> Repo.all()
    |> Enum.flat_map(fn results ->
      results
      |> Map.values()
      |> Enum.map(&Map.get(&1, "data", ""))
      |> Enum.flat_map(&extract_verdict_from_data/1)
    end)
  end

  defp analyze_verdicts(verdicts) do
    freqs = Enum.frequencies(verdicts)
    total = length(verdicts)
    pass_rate = Map.get(freqs, "pass", 0) / max(total, 1)
    fail_rate = Map.get(freqs, "fail", 0) / max(total, 1)

    cond do
      pass_rate >= 0.8 -> :slow_down
      fail_rate >= 0.6 -> :speed_up
      true -> :no_change
    end
  end

  defp adjust_sources(source_ids, adjustment) do
    senses = Repo.all(from s in Sense, where: s.id in ^source_ids)

    Enum.each(senses, fn sense ->
      current_interval = sense.config["interval"] || 60_000

      new_interval =
        case adjustment do
          :speed_up ->
            max(round(current_interval * @speedup_factor), @min_interval)

          :slow_down ->
            min(round(current_interval * @slowdown_factor), @max_interval)
        end

      if new_interval != current_interval do
        apply_interval_change(sense, current_interval, new_interval, adjustment)
      end
    end)
  end

  defp apply_interval_change(sense, current_interval, new_interval, adjustment) do
    new_config = Map.put(sense.config, "interval", new_interval)

    case sense |> Sense.changeset(%{config: new_config}) |> Repo.update() do
      {:ok, _} ->
        Logger.info(
          "[SenseFeedback] Adjusted #{sense.name} interval: #{current_interval}ms → #{new_interval}ms (#{adjustment})"
        )

      {:error, _} ->
        :ok
    end
  end

  defp extract_verdict_from_data(data) do
    case Regex.run(~r/verdict:\s*"(\w+)"/, data) do
      [_, v] -> [v]
      _ -> []
    end
  end
end
