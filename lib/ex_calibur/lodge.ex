defmodule ExCalibur.Lodge do
  @moduledoc "Context for Lodge workspace cards."

  import Ecto.Query

  alias ExCalibur.Lodge.Card
  alias ExCalibur.Repo

  def list_cards(opts \\ []) do
    query =
      from(c in Card,
        where: c.status == "active",
        order_by: [desc: c.pinned, desc: c.inserted_at]
      )

    query =
      case Keyword.get(opts, :type) do
        nil -> query
        type -> where(query, [c], c.type == ^type)
      end

    Repo.all(query)
  end

  def get_card!(id), do: Repo.get!(Card, id)

  def create_card(attrs) do
    %Card{} |> Card.changeset(attrs) |> Repo.insert()
  end

  def update_card(%Card{} = card, attrs) do
    card |> Card.changeset(attrs) |> Repo.update()
  end

  def dismiss_card(%Card{} = card) do
    update_card(card, %{status: "dismissed"})
  end

  def toggle_pin(%Card{} = card) do
    update_card(card, %{pinned: !card.pinned})
  end

  def delete_card(%Card{} = card) do
    Repo.delete(card)
  end

  def post_card(attrs) do
    case create_card(attrs) do
      {:ok, card} ->
        Phoenix.PubSub.broadcast(ExCalibur.PubSub, "lodge", {:lodge_card_posted, card})
        {:ok, card}

      error ->
        error
    end
  end

  def toggle_checklist_item(%Card{type: "checklist"} = card, index) do
    items = card.metadata["items"] || []

    updated_items =
      List.update_at(items, index, fn item ->
        Map.put(item, "checked", !item["checked"])
      end)

    update_card(card, %{metadata: Map.put(card.metadata, "items", updated_items)})
  end
end
