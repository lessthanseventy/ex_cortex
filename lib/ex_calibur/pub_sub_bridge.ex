defmodule ExCalibur.PubSubBridge do
  @moduledoc """
  Bridges Excellence.PubSub events into ExCalibur.PubSub topics.

  Subscribes to ex_cellence's decision broadcast and fans out to the
  topics that LiveViews subscribe to: evaluation:results, lore, quest_runs.
  """
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(Excellence.PubSub, "excellence:decisions")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:excellence_decision, _payload}, state) do
    Phoenix.PubSub.broadcast(ExCalibur.PubSub, "evaluation:results", :refresh)
    Phoenix.PubSub.broadcast(ExCalibur.PubSub, "lore", :refresh)
    Phoenix.PubSub.broadcast(ExCalibur.PubSub, "quest_runs", :refresh)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
