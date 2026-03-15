defmodule ExCortexTUI.Screens.Memory do
  @moduledoc "Memory screen: lists recent engrams with title, category, and importance."

  alias ExCortexTUI.Components.KeyHints
  alias ExCortexTUI.Components.Panel
  alias ExCortexTUI.Components.Status

  def render(_state) do
    content = fetch_memory()

    hints =
      KeyHints.render([
        {"c", "Cortex"},
        {"n", "Neurons"},
        {"t", "Thoughts"},
        {"s", "Senses"},
        {"q", "Quit"}
      ])

    Enum.join([Panel.render("Memory — Recent Engrams", content), "", hints], "\n")
  end

  defp fetch_memory do
    engrams = ExCortex.Memory.list_engrams(limit: 20)

    if Enum.empty?(engrams) do
      Status.render(:amber, "No engrams stored yet")
    else
      header =
        "#{String.pad_trailing("TITLE", 34)}  #{String.pad_trailing("CATEGORY", 14)}  IMP"

      divider = String.duplicate("─", 56)

      rows =
        Enum.map_join(engrams, "\n", fn e ->
          title = truncate(e.title || "(untitled)", 34)
          category = truncate(e.category || "—", 14)
          importance = importance_bar(e.importance)

          "#{String.pad_trailing(title, 34)}  #{String.pad_trailing(category, 14)}  #{importance}"
        end)

      Enum.join([header, divider, rows], "\n")
    end
  rescue
    _ -> Status.render(:red, "Unavailable — DB not connected")
  end

  defp importance_bar(nil), do: "·····"

  defp importance_bar(n) when is_integer(n) do
    filled = min(max(n, 0), 5)
    String.duplicate("█", filled) <> String.duplicate("·", 5 - filled)
  end

  defp importance_bar(_), do: "·····"

  defp truncate(nil, _), do: ""
  defp truncate(s, max) when byte_size(s) <= max, do: s
  defp truncate(s, max), do: String.slice(s, 0, max - 1) <> "…"
end
