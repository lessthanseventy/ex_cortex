defmodule ExCalibur.LoreTriggerRunner do
  @moduledoc """
  Listens for new lore entries and fires any quests with trigger: "lore"
  whose lore_trigger_tags overlap the entry's tags.
  """
  use GenServer

  alias ExCalibur.QuestRunner
  alias ExCalibur.Quests

  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExCalibur.PubSub, "lore_triggers")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:lore_entry_created, entry}, state) do
    try do
      Quests.list_quests()
      |> Enum.filter(fn q ->
        q.trigger == "lore" && q.status == "active" && tags_match?(q.lore_trigger_tags, entry.tags)
      end)
      |> Enum.each(fn quest ->
        Logger.info("[LoreTriggerRunner] Firing quest #{quest.id} (#{quest.name}) on lore entry #{entry.id}")
        Task.start(fn -> QuestRunner.run(quest, entry.body || "") end)
      end)
    rescue
      e ->
        Logger.warning("[LoreTriggerRunner] Error processing lore entry #{entry.id}: #{inspect(e)}")
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # empty trigger_tags = match all entries
  defp tags_match?([], _entry_tags), do: true
  defp tags_match?(trigger_tags, entry_tags), do: Enum.any?(trigger_tags, &(&1 in entry_tags))
end
