defmodule Mix.Tasks.Tui do
  @shortdoc "Start TUI"
  @moduledoc "Start ExCortex with the interactive TUI."
  use Mix.Task

  def run(_args) do
    # Suppress console logs before boot — TUI will capture them in the log buffer
    Logger.configure(level: :none)
    System.put_env("EX_CORTEX_MODE", "tui")

    # Disable Erlang's shell terminal management so we can set raw mode
    # The shell driver (user_drv) controls terminal settings and fights stty
    :init.notify_when_started(self())
    Application.put_env(:elixir, :ansi_enabled, true)
    Mix.Tasks.Run.run(["--no-halt"])
  end
end
