if Code.ensure_loaded?(Ratatouille) do
defmodule Mix.Tasks.Tui do
  @shortdoc "Start TUI"
  @moduledoc "Start ExCortex with the interactive Ratatouille TUI."
  use Mix.Task

  require Logger

  def run(_args) do
    Logger.configure(level: :none)
    System.put_env("EX_CORTEX_MODE", "tui")

    # termbox doesn't recognize tmux-256color — set xterm-256color (compatible)
    if String.contains?(System.get_env("TERM", ""), "tmux") do
      System.put_env("TERM", "xterm-256color")
    end

    # Boot the app (DB, PubSub, etc. but NOT the TUI itself)
    Application.ensure_all_started(:ex_cortex)

    # Set up log buffer for the Logs screen
    ExCortexTUI.LogBuffer.start_link()
    :logger.add_handler(:tui_buffer, ExCortexTUI.LogHandler, %{})
    :logger.set_handler_config(:default, %{level: :none})
    Logger.configure(level: :debug)

    # Run Ratatouille (blocks until quit)
    Ratatouille.run(ExCortexTUI.App,
      quit_events: [
        {:key, Ratatouille.Constants.key(:ctrl_c)},
        {:ch, ?q}
      ],
      shutdown: :system
    )
  end
end
end
