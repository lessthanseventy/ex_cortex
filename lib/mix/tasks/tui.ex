defmodule Mix.Tasks.Tui do
  @shortdoc "Start TUI"
  @moduledoc "Start ExCortex with the interactive TUI."
  use Mix.Task

  def run(_args) do
    Logger.configure(level: :none)
    System.put_env("EX_CORTEX_MODE", "tui")

    # Set terminal to raw mode BEFORE the app starts
    # System.cmd inherits mix's stdin which IS the terminal
    System.cmd("stty", ["-icanon", "-echo"])

    Mix.Tasks.Run.run(["--no-halt"])
  end
end
