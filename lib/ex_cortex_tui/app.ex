defmodule ExCortexTUI.App do
  @moduledoc "Owl-based terminal UI for ExCortex."

  use GenServer

  alias ExCortexTUI.Router

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "daydreams")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "signals")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "memory")

    state = %{screen: :cortex}
    render(state)
    schedule_refresh()
    {:ok, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    render(state)
    schedule_refresh()
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    render(state)
    {:noreply, state}
  end

  defp render(state) do
    IO.write(IO.ANSI.clear() <> IO.ANSI.home())

    header =
      IO.ANSI.yellow() <>
        "ExCortex" <>
        IO.ANSI.reset() <>
        "  " <>
        ExCortexTUI.Components.KeyHints.render([
          {"c", "cortex"},
          {"n", "neurons"},
          {"t", "thoughts"},
          {"m", "memory"},
          {"s", "senses"},
          {"i", "instinct"},
          {"g", "guide"},
          {"q", "quit"}
        ])

    content = Router.render(state.screen, state)

    status =
      IO.ANSI.green() <>
        "●" <> IO.ANSI.reset() <> " ready  " <> IO.ANSI.faint() <> "[?] help" <> IO.ANSI.reset()

    IO.puts(header)
    IO.puts(String.duplicate("─", 80))
    IO.puts(content)
    IO.puts(String.duplicate("─", 80))
    IO.puts(status)
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, 10_000)
end
