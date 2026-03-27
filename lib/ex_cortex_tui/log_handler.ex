defmodule ExCortexTUI.LogHandler do
  @moduledoc "Erlang :logger handler that routes log messages to the TUI log buffer."

  def log(%{level: level, msg: msg, meta: meta}, _config) do
    message = format_message(msg)
    time = format_time(meta)
    module = meta |> Map.get(:mfa, {nil, nil, nil}) |> elem(0) |> format_module()
    line = "#{time} [#{level}]#{module} #{message}"

    if Process.whereis(ExCortexTUI.LogBuffer) do
      ExCortexTUI.LogBuffer.append(line)
    end
  end

  defp format_message({:string, msg}), do: IO.chardata_to_string(msg)
  defp format_message({:report, report}), do: inspect(report)
  defp format_message(msg) when is_binary(msg), do: msg
  defp format_message(msg), do: inspect(msg)

  defp format_time(%{time: time}) do
    dt = :calendar.system_time_to_universal_time(time, :microsecond)
    {{_, _, _}, {h, m, s}} = dt
    "#{pad(h)}:#{pad(m)}:#{pad(s)}"
  end

  defp format_time(_), do: "??:??:??"

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: to_string(n)

  defp format_module(nil), do: ""
  defp format_module(mod), do: " [#{mod |> inspect() |> String.replace("Elixir.", "")}]"
end
