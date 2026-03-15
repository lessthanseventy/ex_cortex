defmodule ExCortex.Signals.TriggerRunner do
  @moduledoc """
  Listens for new cortex signal cards and fires any ruminations with trigger: "cortex"
  whose signal_trigger_types/signal_trigger_tags overlap the card's type/tags.
  """
  use GenServer

  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Runner

  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ExCortex.PubSub, "cortex")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:signal_posted, card}, state) do
    try do
      Ruminations.list_ruminations()
      |> Enum.filter(fn q ->
        q.trigger == "cortex" && q.status == "active" &&
          types_match?(q.signal_trigger_types, card.type) &&
          tags_match?(q.signal_trigger_tags, card.tags || [])
      end)
      |> Enum.each(fn rumination ->
        Logger.info(
          "[SignalTriggerRunner] Firing rumination #{rumination.id} (#{rumination.name}) on signal card #{card.id}"
        )

        input = build_input(card)
        Task.start(fn -> Runner.run(rumination, input) end)
      end)
    rescue
      e in [DBConnection.OwnershipError, DBConnection.ConnectionError] ->
        _ = e
        :ok

      e ->
        Logger.warning("[SignalTriggerRunner] Error processing signal card #{card.id}: #{inspect(e)}")
    catch
      :exit, _ -> :ok
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp types_match?([], _card_type), do: true
  defp types_match?(types, card_type), do: card_type in types

  defp tags_match?([], _card_tags), do: true
  defp tags_match?(trigger_tags, card_tags), do: Enum.any?(trigger_tags, &(&1 in card_tags))

  defp build_input(card) do
    tags_str = if card.tags == [], do: "", else: "\nTags: #{Enum.join(card.tags, ", ")}"
    "## #{card.title}\nType: #{card.type}#{tags_str}\n\n#{card.body || ""}"
  end
end
