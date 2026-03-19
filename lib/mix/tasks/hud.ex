defmodule Mix.Tasks.Hud do
  @shortdoc "Start HUD"
  @moduledoc "Start ExCortex HUD (machine-readable dashboard)."
  use Mix.Task

  def run(_args) do
    System.put_env("EX_CORTEX_MODE", "hud")
    Mix.Tasks.Run.run(["--no-halt"])
  end
end
