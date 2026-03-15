defmodule ExCortex.Thoughts.Throttle do
  @moduledoc """
  ETS-based per-thought cooldown. Prevents the same thought from running more than
  once per cooldown window, even when multiple sources fire simultaneously.
  """

  @table :quest_cooldowns
  # 5 minutes — feeds all share the same prediction thought, so cap at one run per window
  @default_cooldown_ms 5 * 60 * 1000

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ok
  end

  @doc """
  Attempt to acquire the right to run `quest_id`.
  Returns `:ok` if allowed, `:cooldown` if still within the cooldown window.
  """
  def acquire(quest_id, cooldown_ms \\ @default_cooldown_ms) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, quest_id) do
      [{^quest_id, last_run}] when now - last_run < cooldown_ms ->
        :cooldown

      _ ->
        :ets.insert(@table, {quest_id, now})
        :ok
    end
  end
end
