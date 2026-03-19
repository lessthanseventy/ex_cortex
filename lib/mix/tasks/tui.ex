defmodule Mix.Tasks.Tui do
  @shortdoc "Start TUI"
  @moduledoc "Start ExCortex with the interactive TUI."
  use Mix.Task

  def run(_args) do
    # Suppress console logs before boot — TUI will capture them in the log buffer
    Logger.configure(level: :none)
    System.put_env("EX_CORTEX_MODE", "tui")
    Mix.Tasks.Run.run(["--no-halt"])
  end
end
