defmodule ExCalibur.LodgeTriggerRunner do
  @moduledoc """
  Listens for new lodge cards and fires any quests with trigger: "lodge"
  whose lodge_trigger_types/lodge_trigger_tags overlap the card's type/tags.
  """
  use GenServer

  alias ExCalibur.QuestRunner
  alias ExCalibur.Quests

  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExCalibur.PubSub, "lodge")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:lodge_card_posted, card}, state) do
    try do
      Quests.list_quests()
      |> Enum.filter(fn q ->
        q.trigger == "lodge" && q.status == "active" &&
          types_match?(q.lodge_trigger_types, card.type) &&
          tags_match?(q.lodge_trigger_tags, card.tags || [])
      end)
      |> Enum.each(fn quest ->
        Logger.info("[LodgeTriggerRunner] Firing quest #{quest.id} (#{quest.name}) on lodge card #{card.id}")
        input = build_input(card)
        Task.start(fn -> QuestRunner.run(quest, input) end)
      end)
    rescue
      e in DBConnection.OwnershipError ->
        _ = e
        :ok

      e ->
        Logger.warning("[LodgeTriggerRunner] Error processing lodge card #{card.id}: #{inspect(e)}")
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp types_match?([], _card_type), do: true
  defp types_match?(types, card_type), do: card_type in types

  defp tags_match?([], _card_tags), do: true
  defp tags_match?(trigger_tags, card_tags), do: Enum.any?(trigger_tags, &(&1 in card_tags))

  defp build_input(card) do
    tags_str = if card.tags != [], do: "\nTags: #{Enum.join(card.tags, ", ")}", else: ""
    "## #{card.title}\nType: #{card.type}#{tags_str}\n\n#{card.body || ""}"
  end
end
