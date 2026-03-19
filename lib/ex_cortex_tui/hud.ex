defmodule ExCortexTUI.HUD do
  @moduledoc """
  Machine-readable dashboard GenServer.
  Periodically gathers system state and prints compact text to stdout.
  Designed for AI consumption via `tmux capture-pane`.
  """

  use GenServer

  import Ecto.Query

  alias ExCortexTUI.HUD.Formatter

  require Logger

  @refresh_interval 5_000

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gather current system state. Public so the TUI HUD screen can reuse it.
  Returns a map with :daydreams, :proposals, :signals, :trust_scores, :errors.
  """
  def gather_state do
    %{
      daydreams: gather_daydreams(),
      proposals: gather_proposals(),
      signals: gather_signals(),
      trust_scores: gather_trust_scores(),
      errors: []
    }
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "daydreams")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "signals")
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "memory")
    schedule_refresh()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:refresh, state) do
    print()
    schedule_refresh()
    {:noreply, state}
  end

  # PubSub messages trigger an immediate refresh
  def handle_info({:daydream_started, _}, state), do: refresh_and_noreply(state)
  def handle_info({:daydream_completed, _}, state), do: refresh_and_noreply(state)
  def handle_info({:signal_updated, _}, state), do: refresh_and_noreply(state)
  def handle_info({:engram_updated, _}, state), do: refresh_and_noreply(state)
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp refresh_and_noreply(state) do
    print()
    {:noreply, state}
  end

  defp print do
    output = Formatter.format(gather_state())
    # Clear screen + cursor home, then print
    IO.write("\e[2J\e[H" <> output <> "\n")
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp gather_daydreams do
    ExCortex.Repo.all(
      from(d in ExCortex.Ruminations.Daydream,
        where: d.status in ["running", "pending"],
        order_by: [desc: d.inserted_at],
        limit: 10,
        preload: [:rumination]
      )
    )
  rescue
    _e -> []
  end

  defp gather_proposals do
    ExCortex.Ruminations.list_proposals(status: "pending")
  rescue
    _e -> []
  end

  defp gather_signals do
    Enum.take(ExCortex.Signals.list_signals(), 10)
  rescue
    _e -> []
  end

  defp gather_trust_scores do
    ExCortex.TrustScorer.list_scores()
  rescue
    _e -> []
  end
end
