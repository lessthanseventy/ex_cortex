defmodule ExCortexTUI.Components.KeyHints do
  @moduledoc "Keyboard shortcut hints bar."

  def render(hints) do
    Enum.map_join(hints, "  ", fn {key, label} ->
      IO.ANSI.cyan() <> "[#{key}]" <> IO.ANSI.reset() <> " #{label}"
    end)
  end
end
