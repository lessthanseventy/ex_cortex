defmodule ExCortex.LocalDate do
  @moduledoc "Returns the system's local date, not UTC. Used for daily note lookups."

  @doc "Today's local date."
  def today do
    case System.cmd("date", ["-I"]) do
      {date_str, 0} -> Date.from_iso8601!(String.trim(date_str))
      _ -> Date.utc_today()
    end
  end

  @doc "Yesterday's local date."
  def yesterday, do: Date.add(today(), -1)
end
