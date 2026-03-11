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

    query =
      case Keyword.get(opts, :tags) do
        nil -> query
        [] -> query
        tags when is_list(tags) -> where(query, [c], fragment("? && ?", c.tags, ^tags))
        _ -> query
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

  def sync_proposals do
    pending = ExCalibur.Quests.list_proposals(status: "pending")

    existing_ids =
      [type: "proposal"]
      |> list_cards()
      |> MapSet.new(& &1.metadata["proposal_id"])

    for proposal <- pending, proposal.id not in existing_ids do
      create_card(%{
        type: "proposal",
        title: proposal.description,
        body: proposal.details["suggestion"] || "",
        source: "quest",
        quest_id: proposal.quest_id,
        metadata: %{
          "proposal_id" => proposal.id,
          "proposal_type" => proposal.type
        }
      })
    end
  end

  def sync_augury do
    augury_entry =
      [tags: ["augury"], sort: "newest"]
      |> ExCalibur.Lore.list_entries()
      |> List.first()

    existing = [type: "augury"] |> list_cards() |> List.first()

    cond do
      is_nil(augury_entry) ->
        :noop

      existing ->
        update_card(existing, %{title: augury_entry.title, body: augury_entry.body})

      true ->
        create_card(%{
          type: "augury",
          title: augury_entry.title,
          body: augury_entry.body,
          source: "lore",
          pinned: true
        })
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
