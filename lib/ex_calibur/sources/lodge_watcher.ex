defmodule ExCalibur.Sources.LodgeWatcher do
  @moduledoc "Source adapter that watches Lodge cards for new/changed items."
  @behaviour ExCalibur.Sources.Behaviour

  import Ecto.Query

  alias ExCalibur.Lodge.Card
  alias ExCalibur.Repo
  alias ExCalibur.Sources.SourceItem

  @impl true
  def init(config) do
    last_seen_at = Map.get(config, "last_seen_at")
    {:ok, %{last_seen_at: last_seen_at}}
  end

  @impl true
  def fetch(state, config) do
    type_filter = config["type_filter"]
    tag_filter = config["tag_filter"]

    query =
      from(c in Card,
        where: c.status == "active",
        order_by: [asc: c.updated_at]
      )

    query =
      case type_filter do
        nil -> query
        types when is_list(types) and types != [] -> where(query, [c], c.type in ^types)
        _ -> query
      end

    query =
      case tag_filter do
        nil -> query
        tags when is_list(tags) and tags != [] -> where(query, [c], fragment("? && ?", c.tags, ^tags))
        _ -> query
      end

    query =
      case state.last_seen_at do
        nil ->
          query

        last_seen_at ->
          ndt = NaiveDateTime.from_iso8601!(last_seen_at)
          where(query, [c], c.updated_at > ^ndt)
      end

    cards = Repo.all(query)

    items =
      Enum.map(cards, fn card ->
        %SourceItem{
          source_id: config["source_id"],
          type: "lodge_card",
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
end
