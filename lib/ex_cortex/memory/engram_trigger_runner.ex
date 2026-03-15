defmodule ExCortex.Memory.EngramTriggerRunner do
  @moduledoc """
  Listens for new memory engrams and fires any thoughts with trigger: "memory"
  whose lore_trigger_tags overlap the entry's tags.
  """
  use GenServer

  alias ExCortex.Thoughts
  alias ExCortex.Thoughts.Runner

  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "lore_triggers")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:lore_entry_created, entry}, state) do
    try do
      Thoughts.list_thoughts()
      |> Enum.filter(fn q ->
        q.trigger == "memory" && q.status == "active" && tags_match?(q.lore_trigger_tags, entry.tags)
      end)
      |> Enum.each(fn thought ->
        Logger.info("[EngramTriggerRunner] Firing thought #{thought.id} (#{thought.name}) on engram #{entry.id}")
        Task.start(fn -> Runner.run(thought, entry.body || "") end)
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
