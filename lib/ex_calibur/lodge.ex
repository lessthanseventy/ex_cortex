defmodule ExCalibur.Lodge do
  @moduledoc "Context for Lodge workspace cards."

  import Ecto.Query

  alias ExCalibur.Lodge.Card
  alias ExCalibur.Lodge.CardVersion
  alias ExCalibur.Obsidian.Sync
  alias ExCalibur.Repo

  def list_cards(opts \\ []) do
    query =
      from(c in Card,
        where: c.status == "active",
        order_by: [desc: c.pinned, asc: c.pin_order, desc: c.inserted_at]
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

  def upsert_card(%{pin_slug: slug} = attrs) when is_binary(slug) and slug != "" do
    case Repo.one(from(c in Card, where: c.pin_slug == ^slug)) do
      nil ->
        create_card(attrs)

      existing ->
        %CardVersion{}
        |> CardVersion.changeset(%{
          card_id: existing.id,
          body: existing.body,
          metadata: existing.metadata,
          replaced_at: DateTime.truncate(DateTime.utc_now(), :second)
        })
        |> Repo.insert()

        update_card(existing, attrs)
    end
  end

  def upsert_card(attrs), do: create_card(attrs)

  def post_card(%{pin_slug: slug} = attrs) when is_binary(slug) and slug != "" do
    case upsert_card(attrs) do
      {:ok, card} ->
        Phoenix.PubSub.broadcast(ExCalibur.PubSub, "lodge", {:lodge_card_posted, card})

        Sync.sync_lodge_card(card)

        {:ok, card}

      error ->
        error
    end
  end

  def post_card(attrs) do
    case create_card(attrs) do
      {:ok, card} ->
        Phoenix.PubSub.broadcast(ExCalibur.PubSub, "lodge", {:lodge_card_posted, card})

        Sync.sync_lodge_card(card)

        {:ok, card}

      error ->
        error
    end
  end

  def sync_proposals do
    pending = ExCalibur.Quests.list_proposals(status: "pending")

    existing_cards =
      [type: "proposal"]
      |> list_cards()
      |> Map.new(&{&1.metadata["proposal_id"], &1})

    for proposal <- pending do
      title = proposal_card_title(proposal)
      body = proposal_card_body(proposal)

      case Map.get(existing_cards, proposal.id) do
        nil -> create_proposal_card(proposal, title, body)
        existing -> maybe_update_proposal_card(existing, title, body)
      end
    end
  end

  defp create_proposal_card(proposal, title, body) do
    create_card(%{
      type: "proposal",
      title: title,
      body: body,
      source: "quest",
      quest_id: proposal.quest_id,
      metadata: %{"proposal_id" => proposal.id, "proposal_type" => proposal.type}
    })
  end

  defp maybe_update_proposal_card(existing, title, body) do
    if existing.title != title or existing.body != body do
      update_card(existing, %{title: title, body: body})
    end
  end

  defp proposal_card_title(%{tool_name: "create_github_issue", tool_args: %{"title" => t}}), do: t
  defp proposal_card_title(%{description: desc}), do: desc

  defp proposal_card_body(%{tool_name: "create_github_issue", tool_args: %{"body" => b}}), do: b
  defp proposal_card_body(%{details: %{"suggestion" => s}}) when is_binary(s), do: s
  defp proposal_card_body(_), do: ""

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
