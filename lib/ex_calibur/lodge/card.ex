defmodule ExCalibur.Lodge.Card do
  use Ecto.Schema

  import Ecto.Changeset

  @valid_types ~w(note checklist meeting alert link proposal augury)
  @valid_statuses ~w(active dismissed archived)

  schema "lodge_cards" do
    field :type, :string
    field :title, :string
    field :body, :string, default: ""
    field :metadata, :map, default: %{}
    field :pinned, :boolean, default: false
    field :source, :string
    field :quest_id, :integer
    field :status, :string, default: "active"

    timestamps()
  end

  def changeset(card, attrs) do
    card
    |> cast(attrs, [:type, :title, :body, :metadata, :pinned, :source, :quest_id, :status])
    |> validate_required([:type, :title, :source, :status])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
  end
end
