defmodule Mix.Tasks.Cortex do
  @shortdoc "Start ExCortex terminal UI"

  @moduledoc "Start the ExCortex terminal UI."
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    {:ok, _} = ExCortexTUI.App.start_link()

    # Block until user quits
    receive do
      :never -> :ok
    end
  end
end
