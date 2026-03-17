defmodule ExCortex.Signals do
  @moduledoc "Context for Cortex workspace cards."

  import Ecto.Query

  alias ExCortex.Obsidian.Sync
  alias ExCortex.Repo
  alias ExCortex.Signals.Signal
  alias ExCortex.Signals.Version

  def list_signals(opts \\ []) do
    query =
      from(c in Signal,
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

  def get_signal!(id), do: Repo.get!(Signal, id)

  def create_signal(attrs) do
    %Signal{} |> Signal.changeset(attrs) |> Repo.insert()
  end

  def update_signal(%Signal{} = card, attrs) do
    card |> Signal.changeset(attrs) |> Repo.update()
  end

  def dismiss_signal(%Signal{} = card) do
    update_signal(card, %{status: "dismissed"})
  end

  def toggle_pin(%Signal{} = card) do
    update_signal(card, %{pinned: !card.pinned})
  end

  def delete_signal(%Signal{} = card) do
    Repo.delete(card)
  end

  def upsert_signal(%{pin_slug: slug} = attrs) when is_binary(slug) and slug != "" do
    case Repo.one(from(c in Signal, where: c.pin_slug == ^slug)) do
      nil ->
        create_signal(attrs)

      existing ->
        %Version{}
        |> Version.changeset(%{
          card_id: existing.id,
          body: existing.body,
          metadata: existing.metadata,
          replaced_at: DateTime.truncate(DateTime.utc_now(), :second)
        })
        |> Repo.insert()

        update_signal(existing, attrs)
    end
  end

  def upsert_signal(attrs), do: create_signal(attrs)

  def post_signal(%{pin_slug: slug} = attrs) when is_binary(slug) and slug != "" do
    case upsert_signal(attrs) do
      {:ok, card} ->
        Phoenix.PubSub.broadcast(ExCortex.PubSub, "cortex", {:signal_posted, card})

        Sync.sync_signal(card)

        {:ok, card}

      error ->
        error
    end
  end

  def post_signal(%{pin_slug: slug} = attrs) when is_binary(slug) and slug != "" do
    upsert_pinned_signal(attrs, slug)
  end

  def post_signal(%{"pin_slug" => slug} = attrs) when is_binary(slug) and slug != "" do
    upsert_pinned_signal(attrs, slug)
  end

  def post_signal(attrs) do
    case create_signal(attrs) do
      {:ok, card} ->
        Phoenix.PubSub.broadcast(ExCortex.PubSub, "cortex", {:signal_posted, card})
        Sync.sync_signal(card)
        {:ok, card}

      error ->
        error
    end
  end

  defp upsert_pinned_signal(attrs, slug) do
    case Repo.one(from(s in Signal, where: s.pin_slug == ^slug)) do
      nil ->
        # First time — create with pinned=true
        attrs = Map.merge(attrs, %{pinned: true, pin_slug: slug})

        case create_signal(attrs) do
          {:ok, card} ->
            Phoenix.PubSub.broadcast(ExCortex.PubSub, "cortex", {:signal_posted, card})
            Sync.sync_signal(card)
            {:ok, card}

          error ->
            error
        end

      existing ->
        # Update in place — preserve id, pinned status, pin_order
        update_attrs =
          attrs
          |> Map.drop([:pin_slug, "pin_slug", :pinned, "pinned", :pin_order, "pin_order"])
          |> Map.put(:status, "active")

        case update_signal(existing, update_attrs) do
          {:ok, card} ->
            Phoenix.PubSub.broadcast(ExCortex.PubSub, "cortex", {:signal_posted, card})
            Sync.sync_signal(card)
            {:ok, card}

          error ->
            error
        end
    end
  end

  def sync_proposals do
    pending = ExCortex.Ruminations.list_proposals(status: "pending")

    existing_cards =
      [type: "proposal"]
      |> list_signals()
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
    create_signal(%{
      type: "proposal",
      title: title,
      body: body,
      source: "rumination",
      rumination_id: proposal.synapse_id,
      metadata: %{"proposal_id" => proposal.id, "proposal_type" => proposal.type}
    })
  end

  defp maybe_update_proposal_card(existing, title, body) do
    if existing.title != title or existing.body != body do
      update_signal(existing, %{title: title, body: body})
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
      |> ExCortex.Memory.list_engrams()
      |> List.first()

    existing = [type: "augury"] |> list_signals() |> List.first()

    cond do
      is_nil(augury_entry) ->
        :noop

      existing ->
        update_signal(existing, %{title: augury_entry.title, body: augury_entry.body})

      true ->
        create_signal(%{
          type: "augury",
          title: augury_entry.title,
          body: augury_entry.body,
          source: "memory",
          pinned: true
        })
    end
  end

  def toggle_checklist_item(%Signal{type: "checklist"} = card, index) do
    items = card.metadata["items"] || []

    updated_items =
      List.update_at(items, index, fn item ->
        Map.put(item, "checked", !item["checked"])
      end)

    update_signal(card, %{metadata: Map.put(card.metadata, "items", updated_items)})
  end
end
