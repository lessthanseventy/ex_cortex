defmodule ExCortex.Senses.SignalWatcher do
  @moduledoc "Source adapter that watches signal cards for new/changed items."
  @behaviour ExCortex.Senses.Behaviour

  import Ecto.Query

  alias ExCortex.Repo
  alias ExCortex.Senses.Item
  alias ExCortex.Signals.Signal

  @impl true
  def init(config) do
    last_seen_at = Map.get(config, "last_seen_at")
    {:ok, %{last_seen_at: last_seen_at}}
  end

  @impl true
  def fetch(state, config) do
    type_filter = config["type_filter"]
    tag_filter = config["tag_filter"]

    cards =
      from(c in Signal, where: c.status == "active", order_by: [asc: c.updated_at])
      |> filter_by_type(type_filter)
      |> filter_by_tags(tag_filter)
      |> filter_since(state.last_seen_at)
      |> Repo.all()

    items =
      Enum.map(cards, fn card ->
        %Item{
          source_id: config["source_id"],
          type: "signal",
          content: card.body || "",
          metadata: %{
            card_type: card.type,
            title: card.title,
            tags: card.tags,
            pinned: card.pinned,
            card_id: card.id
          }
        }
      end)

    new_last_seen_at =
      case cards do
        [] -> state.last_seen_at
        _ -> cards |> List.last() |> Map.get(:updated_at) |> NaiveDateTime.to_iso8601()
      end

    {:ok, items, %{state | last_seen_at: new_last_seen_at}}
  end

  defp filter_by_type(query, types) when is_list(types) and types != [], do: where(query, [c], c.type in ^types)
  defp filter_by_type(query, _), do: query

  defp filter_by_tags(query, tags) when is_list(tags) and tags != [],
    do: where(query, [c], fragment("? && ?", c.tags, ^tags))

  defp filter_by_tags(query, _), do: query

  defp filter_since(query, nil), do: query

  defp filter_since(query, last_seen_at) do
    ndt = NaiveDateTime.from_iso8601!(last_seen_at)
    where(query, [c], c.updated_at > ^ndt)
  end
end
