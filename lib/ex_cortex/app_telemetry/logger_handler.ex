defmodule ExCortex.AppTelemetry.LoggerHandler do
  @moduledoc """
  Erlang Logger handler that forwards :warning and :error events to AppTelemetry.
  Registered via :logger.add_handler/3 in AppTelemetry.init/1.
  """

  @doc "Called by the Erlang logger for each matching log event."
  def log(%{level: level, msg: msg, meta: meta}, %{config: %{pid: pid}}) do
    # Don't capture logs originating from AppTelemetry itself
    module = Map.get(meta, :module, :unknown)

    if module != ExCortex.AppTelemetry do
      message = format_msg(msg)
      send(pid, {:log_event, level, message, module, System.system_time(:second)})
    end

    :ok
  end

  def log(_event, _config), do: :ok

  defp format_msg({:string, chardata}), do: chardata |> IO.chardata_to_string() |> String.slice(0, 300)
  defp format_msg({:report, report}), do: report |> inspect(limit: 50) |> String.slice(0, 300)
  defp format_msg(other), do: other |> inspect(limit: 50) |> String.slice(0, 300)
end
