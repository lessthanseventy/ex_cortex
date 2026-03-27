defmodule ExCortexTUI.Screens.Logs do
  @moduledoc "Log viewer screen — shows recent log output."
  @behaviour ExCortexTUI.Screen

  @impl true
  def init(_) do
    %{scroll: 0}
  end

  @impl true
  def render(_state) do
    lines = ExCortexTUI.LogBuffer.get_lines(40)

    header = [Owl.Data.tag("Logs", [:bright, :yellow]), "\n\n"]

    log_lines =
      if Enum.empty?(lines) do
        [Owl.Data.tag("  No log output yet", :faint)]
      else
        Enum.map_intersperse(lines, "\n", &colorize_log_line/1)
      end

    List.flatten([header | log_lines])
  end

  @impl true
  def handle_key(_key, state), do: {:noreply, state}

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp colorize_log_line(line) do
    cond do
      String.contains?(line, "[error]") -> Owl.Data.tag(line, :red)
      String.contains?(line, "[warning]") -> Owl.Data.tag(line, :yellow)
      String.contains?(line, "[info]") -> line
      true -> Owl.Data.tag(line, :faint)
    end
  end
end
