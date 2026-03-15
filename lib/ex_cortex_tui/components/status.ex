defmodule ExCortexTUI.Components.Status do
  @moduledoc "Colored status dot with label."

  def render(color, label) do
    dot =
      case color do
        :green -> IO.ANSI.green() <> "●" <> IO.ANSI.reset()
        :amber -> IO.ANSI.yellow() <> "●" <> IO.ANSI.reset()
        :red -> IO.ANSI.red() <> "●" <> IO.ANSI.reset()
        :cyan -> IO.ANSI.cyan() <> "●" <> IO.ANSI.reset()
        _ -> "●"
      end

    "#{dot} #{label}"
  end
end
