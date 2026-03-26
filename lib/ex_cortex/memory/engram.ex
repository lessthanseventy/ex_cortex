defmodule ExCortex.Memory.Engram do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "engrams" do
    field :rumination_id, :integer
    field :title, :string
    field :body, :string, default: ""
    field :tags, {:array, :string}, default: []
    field :importance, :integer
    field :source, :string, default: "thought"

    # Tiered memory fields
    field :impression, :string
    field :recall, :string
    field :category, :string, default: "semantic"
    field :cluster_name, :string
    field :daydream_id, :integer
    field :embedding, Pgvector.Ecto.Vector

    timestamps()
  end

  @required [:title]
  @optional [
    :rumination_id,
    :body,
    :tags,
    :importance,
    :source,
    :impression,
    :recall,
    :category,
    :cluster_name,
    :daydream_id,
    :embedding
  ]

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:source, ~w(rumination manual step extraction muse wonder))
    |> validate_inclusion(:category, ~w(semantic episodic procedural conversational))
    |> validate_number(:importance, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
  end
end
