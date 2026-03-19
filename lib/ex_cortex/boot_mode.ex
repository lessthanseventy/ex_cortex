defmodule ExCortex.BootMode do
  @moduledoc "Parses CLI args to determine which supervision subtree to start."

  def parse(["server" | _]), do: :server
  def parse(["tui" | _]), do: :tui
  def parse(["hud" | _]), do: :hud
  def parse(_), do: :full

  def current do
    case System.get_env("EX_CORTEX_MODE") do
      nil -> parse(System.argv())
      mode -> parse([mode])
    end
  end
end
