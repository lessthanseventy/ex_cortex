defmodule ExCortexTUI.Components.Panel do
  @moduledoc "Bordered panel with title, rendered in terminal."

  def render(title, content, opts \\ []) do
    width = Keyword.get(opts, :width, 60)
    title_len = String.length(title)
    border_len = max(width - title_len - 4, 1)

    header = "┌─ #{title} #{String.duplicate("─", border_len)}┐"
    footer = "└#{String.duplicate("─", width)}┘"

    body =
      content
      |> String.split("\n")
      |> Enum.map(fn line ->
        padded = String.pad_trailing(String.slice(line, 0, width - 4), width - 4)
        "│ #{padded} │"
      end)

    Enum.join([header | body] ++ [footer], "\n")
  end
end
