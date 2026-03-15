defmodule ExCortex.Memory.EngramTriggerRunner do
  @moduledoc """
  Listens for new memory engrams and fires any ruminations with trigger: "memory"
  whose engram_trigger_tags overlap the entry's tags.
  """
  use GenServer

  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Runner

  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "engram_triggers")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:engram_created, entry}, state) do
    try do
      Ruminations.list_ruminations()
      |> Enum.filter(fn q ->
        q.trigger == "memory" && q.status == "active" && tags_match?(q.engram_trigger_tags, entry.tags)
      end)
      |> Enum.each(fn rumination ->
        Logger.info("[EngramTriggerRunner] Firing rumination #{rumination.id} (#{rumination.name}) on engram #{entry.id}")
        Task.start(fn -> Runner.run(rumination, entry.body || "") end)
      end)
    rescue
      e in DBConnection.OwnershipError ->
        _ = e
        :ok

      e ->
        Logger.warning("[EngramTriggerRunner] Error processing engram #{entry.id}: #{inspect(e)}")
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # empty trigger_tags = match all entries
  defp tags_match?([], _entry_tags), do: true
  defp tags_match?(trigger_tags, entry_tags), do: Enum.any?(trigger_tags, &(&1 in entry_tags))
end
