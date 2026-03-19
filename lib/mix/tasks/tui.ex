defmodule Mix.Tasks.Tui do
  @shortdoc "Start TUI"
  @moduledoc "Start ExCortex with the interactive TUI."
  use Mix.Task

  def run(_args) do
    System.put_env("EX_CORTEX_MODE", "tui")
    Mix.Tasks.Run.run(["--no-halt"])
  end
end
