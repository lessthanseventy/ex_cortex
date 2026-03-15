defmodule ExCortex.Lexicon.Axiom do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "axioms" do
    field :name, :string
    field :description, :string
    field :content, :string, default: ""
    field :content_type, :string, default: "text"
    field :tags, {:array, :string}, default: []
    field :filename, :string
    timestamps()
  end

  @required [:name]
  @optional [:description, :content, :content_type, :tags, :filename]

  def changeset(axiom, attrs) do
    axiom
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:content_type, ~w(text markdown csv json))
    |> unique_constraint(:name)
  end
end
