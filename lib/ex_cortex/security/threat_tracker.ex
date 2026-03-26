defmodule ExCortex.Security.ThreatTracker do
  @moduledoc """
  Per-daydream threat scoring with time decay.
  ETS-backed for fast reads from middleware hot path.
  """
  use GenServer

  require Logger

  @table :threat_scores
  @decay_factor 0.95
  @decay_interval_ms 60_000
  @default_warn_threshold 5.0
  @default_halt_threshold 10.0

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def score(daydream_id) do
    case :ets.lookup(@table, daydream_id) do
      [{_, score, _timestamp}] -> score
      [] -> 0.0
    end
  rescue
    ArgumentError -> 0.0
  end

  def increment(daydream_id, amount) do
    current = score(daydream_id)
    :ets.insert(@table, {daydream_id, current + amount, System.monotonic_time(:millisecond)})
  rescue
    ArgumentError -> :ok
  end

  def check(daydream_id) do
    s = score(daydream_id)
    halt_threshold = resolve_threshold(:halt)
    warn_threshold = resolve_threshold(:warn)

    cond do
      s >= halt_threshold -> :halt
      s >= warn_threshold -> :warn
      true -> :ok
    end
  end

  def clear(daydream_id) do
    :ets.delete(@table, daydream_id)
  rescue
    ArgumentError -> :ok
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set])
    schedule_decay()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:decay, state) do
    decay_all()
    schedule_decay()
    {:noreply, state}
  end

  defp decay_all do
    @table
    |> :ets.tab2list()
    |> Enum.each(fn {id, score, ts} ->
      decayed = score * @decay_factor

      if decayed < 0.01 do
        :ets.delete(@table, id)
      else
        :ets.insert(@table, {id, decayed, ts})
      end
    end)
  rescue
    ArgumentError -> :ok
  end

  defp schedule_decay do
    Process.send_after(self(), :decay, @decay_interval_ms)
  end

  defp resolve_threshold(:warn) do
    case ExCortex.Settings.resolve(:threat_warn_threshold, default: nil) do
      val when is_float(val) -> val
      val when is_binary(val) -> String.to_float(val)
      _ -> @default_warn_threshold
    end
  rescue
    _ -> @default_warn_threshold
  end

  defp resolve_threshold(:halt) do
    case ExCortex.Settings.resolve(:threat_halt_threshold, default: nil) do
      val when is_float(val) -> val
      val when is_binary(val) -> String.to_float(val)
      _ -> @default_halt_threshold
    end
  rescue
    _ -> @default_halt_threshold
  end
end
