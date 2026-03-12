defmodule ExCalibur.Lodge.Card do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @valid_types ~w(note checklist meeting alert link proposal augury briefing action_list table media metric freeform)
  @valid_statuses ~w(active dismissed archived)

  schema "lodge_cards" do
    field :type, :string
    field :title, :string
    field :body, :string, default: ""
    field :metadata, :map, default: %{}
    field :pinned, :boolean, default: false
    field :source, :string
    field :quest_id, :integer
    field :tags, {:array, :string}, default: []
    field :status, :string, default: "active"
    field :card_type, :string, default: "briefing"
    field :pin_slug, :string
    field :pin_order, :integer, default: 0
    field :guild_name, :string

    timestamps()
  end

  def changeset(card, attrs) do
    card
    |> cast(attrs, [:type, :title, :body, :metadata, :pinned, :source, :quest_id, :status, :tags, :card_type, :pin_slug, :pin_order, :guild_name])
    |> validate_required([:type, :title, :source, :status])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:pin_slug)
  end
end
