if Code.ensure_loaded?(Ratatouille) do
defmodule Mix.Tasks.Cortex do
  @shortdoc "Start ExCortex terminal UI"

  @moduledoc "Start the ExCortex terminal UI. Alias for `mix tui`."
  use Mix.Task

  @impl true
  def run(args) do
    Mix.Tasks.Tui.run(args)
  end
end
end
