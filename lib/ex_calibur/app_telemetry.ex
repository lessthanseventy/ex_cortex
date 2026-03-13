defmodule ExCalibur.AppTelemetry do
  @moduledoc """
  In-process telemetry ring buffer for the ExCalibur app.

  Captures:
  - LLM call outcomes (model, duration, success/error) — last 500
  - Circuit breaker trips (tool name) — last 100
  - Warnings and errors from Logger, deduplicated by message hash — last 200 each
  - Quest run outcomes from PubSub — last 50

  Instrumentation points:
  - `ExCalibur.LLM.Ollama` calls `record_llm_call/3` and `record_circuit_breaker/1`
  - Logger handler captures :warning/:error level events
  - PubSub subscription receives `{:quest_run_completed, quest_run}` events
  """

  use GenServer

  require Logger

  @max_llm_calls 500
  @max_circuit_breakers 100
  @max_errors 200
  @max_warnings 200
  @max_quest_runs 50

  defstruct llm_calls: [],
            circuit_breakers: [],
            errors: [],
            warnings: [],
            quest_runs: []

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, %__MODULE__{}, Keyword.merge([name: __MODULE__], opts))

  @doc "Record an LLM call outcome. outcome is :ok or {:error, reason}."
  def record_llm_call(model, duration_ms, outcome) do
    safe_cast({:llm_call, %{model: model, duration_ms: duration_ms, outcome: outcome, timestamp: now()}})
  end

  @doc "Record a circuit breaker trip for a tool."
  def record_circuit_breaker(tool_name) do
    safe_cast({:circuit_breaker, %{tool: tool_name, timestamp: now()}})
  end

  @doc "Called by the Logger handler when a warning or error is logged."
  def record_log_event(level, message, module) do
    safe_cast({:log_event, level, message, module, now()})
  end

  @doc "Reset all buffers — used in tests."
  def reset do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.call(__MODULE__, :reset)
    end
  end

  @doc "Return a formatted summary of recent activity within the given time window."
  def recent(opts \\ []) do
    window_hours = Keyword.get(opts, :window_hours, 6)
    cutoff = now() - window_hours * 3600

    case Process.whereis(__MODULE__) do
      nil -> ""
      _ -> GenServer.call(__MODULE__, {:recent, cutoff})
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(state) do
    Phoenix.PubSub.subscribe(ExCalibur.PubSub, "quest_runs")

    :logger.remove_handler(:app_telemetry)

    :logger.add_handler(:app_telemetry, ExCalibur.AppTelemetry.LoggerHandler, %{
      config: %{pid: self()},
      level: :warning
    })

    {:ok, state}
  end

  @impl true
  def handle_cast({:llm_call, entry}, state) do
    {:noreply, %{state | llm_calls: add_to_ring(state.llm_calls, entry, @max_llm_calls)}}
  end

  def handle_cast({:circuit_breaker, entry}, state) do
    {:noreply, %{state | circuit_breakers: add_to_ring(state.circuit_breakers, entry, @max_circuit_breakers)}}
  end

  def handle_cast({:log_event, :warning, message, module, ts}, state) do
    entry = %{level: :warning, message: message, module: module, timestamp: ts, count: 1}
    {:noreply, %{state | warnings: add_dedup(state.warnings, entry, @max_warnings)}}
  end

  def handle_cast({:log_event, :error, message, module, ts}, state) do
    entry = %{level: :error, message: message, module: module, timestamp: ts, count: 1}
    {:noreply, %{state | errors: add_dedup(state.errors, entry, @max_errors)}}
  end

  def handle_cast(_, state), do: {:noreply, state}

  @impl true
  def handle_info({:quest_run_completed, quest_run}, state) do
    quest_name = fetch_quest_name(quest_run.quest_id)
    failed_step = extract_failed_step(quest_run.step_results)

    entry = %{
      quest_name: quest_name,
      status: quest_run.status,
      timestamp: now(),
      failed_step: failed_step
    }

    {:noreply, %{state | quest_runs: add_to_ring(state.quest_runs, entry, @max_quest_runs)}}
  rescue
    _ -> {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def handle_call({:recent, cutoff}, _from, state) do
    {:reply, format_recent(state, cutoff), state}
  end

  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %__MODULE__{}}
  end

  # ---------------------------------------------------------------------------
  # Formatting
  # ---------------------------------------------------------------------------

  defp format_recent(%__MODULE__{} = state, cutoff) do
    sections =
      Enum.reject(
        [
          format_quest_runs(state.quest_runs, cutoff),
          format_circuit_breakers(state.circuit_breakers, cutoff),
          format_llm_errors(state.llm_calls, cutoff),
          format_log_entries(state.errors, state.warnings, cutoff)
        ],
        &(&1 == "")
      )

    Enum.join(sections, "\n\n")
  end

  defp format_quest_runs([], _cutoff), do: ""

  defp format_quest_runs(runs, cutoff) do
    recent = Enum.filter(runs, &(&1.timestamp >= cutoff))
    if recent == [], do: "", else: do_format_quest_runs(recent)
  end

  defp do_format_quest_runs(runs) do
    by_status = Enum.group_by(runs, & &1.status)
    complete = length(Map.get(by_status, "complete", []))
    gated = Map.get(by_status, "gated", [])
    failed = Map.get(by_status, "failed", [])

    summary = "Quest runs: #{complete} complete"
    summary = if gated == [], do: summary, else: summary <> ", #{length(gated)} gated"
    summary = if failed == [], do: summary, else: summary <> ", #{length(failed)} failed"

    problems =
      Enum.map(gated ++ failed, fn r ->
        step_note = if r.failed_step, do: " — #{r.failed_step}", else: ""
        "  #{r.quest_name} (#{r.status})#{step_note}"
      end)

    if problems == [] do
      summary
    else
      summary <> "\n" <> Enum.join(problems, "\n")
    end
  end

  defp format_circuit_breakers([], _cutoff), do: ""

  defp format_circuit_breakers(trips, cutoff) do
    recent = Enum.filter(trips, &(&1.timestamp >= cutoff))
    if recent == [], do: "", else: do_format_circuit_breakers(recent)
  end

  defp do_format_circuit_breakers(trips) do
    by_tool = Enum.group_by(trips, & &1.tool)

    items =
      by_tool
      |> Enum.sort_by(fn {_tool, list} -> -length(list) end)
      |> Enum.map(fn {tool, list} -> "#{tool} ×#{length(list)}" end)

    "Circuit breakers: #{Enum.join(items, ", ")}"
  end

  defp format_llm_errors([], _cutoff), do: ""

  defp format_llm_errors(calls, cutoff) do
    errors = Enum.filter(calls, &(&1.timestamp >= cutoff and &1.outcome != :ok))

    if errors == [], do: "", else: do_format_llm_errors(errors)
  end

  defp do_format_llm_errors(errors) do
    by_model = Enum.group_by(errors, & &1.model)

    items =
      Enum.map(by_model, fn {model, list} -> "#{model} ×#{length(list)}" end)

    "LLM errors: #{Enum.join(items, ", ")}"
  end

  defp format_log_entries(errors, warnings, cutoff) do
    recent_errors = Enum.filter(errors, &(&1.timestamp >= cutoff))
    recent_warnings = Enum.filter(warnings, &(&1.timestamp >= cutoff))
    all = recent_errors ++ recent_warnings

    if all == [], do: "", else: do_format_log_entries(all)
  end

  defp do_format_log_entries(entries) do
    lines =
      entries
      |> Enum.sort_by(& &1.timestamp, :desc)
      |> Enum.take(20)
      |> Enum.map(fn e ->
        count_note = if e.count > 1, do: " (×#{e.count})", else: ""
        level = String.upcase(to_string(e.level))
        "[#{level}] #{e.message}#{count_note}"
      end)

    "Recent log events:\n" <> Enum.join(lines, "\n")
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp add_to_ring(list, item, max), do: Enum.take([item | list], max)

  defp add_dedup(list, item, max) do
    hash = :erlang.phash2({item.level, item.message, item.module})
    item = Map.put(item, :hash, hash)

    case Enum.find_index(list, &(&1.hash == hash)) do
      nil -> Enum.take([item | list], max)
      idx -> List.update_at(list, idx, &%{&1 | count: &1.count + 1, timestamp: item.timestamp})
    end
  end

  defp safe_cast(msg) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.cast(__MODULE__, msg)
    end
  end

  defp now, do: System.system_time(:second)

  defp fetch_quest_name(quest_id) do
    import Ecto.Query

    alias ExCalibur.Quests.Quest

    case ExCalibur.Repo.one(from q in Quest, where: q.id == ^quest_id, select: q.name) do
      nil -> "Quest ##{quest_id}"
      name -> name
    end
  rescue
    _ -> "Quest ##{quest_id}"
  end

  defp extract_failed_step(step_results) when is_map(step_results) do
    step_results
    |> Enum.find(fn {_idx, result} ->
      Map.get(result, "status") in ["error", "gated"]
    end)
    |> case do
      {_idx, result} when is_map(result) ->
        text = Map.get(result, "data") || Map.get(result, "reason") || ""
        text |> to_string() |> String.slice(0, 80) |> String.replace(~r/\s+/, " ")

      _ ->
        nil
    end
  end

  defp extract_failed_step(_), do: nil
end
