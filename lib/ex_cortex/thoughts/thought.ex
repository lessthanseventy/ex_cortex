defmodule ExCortex.Thoughts.Thought do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "thoughts" do
    field :question, :string
    field :answer, :string
    field :scope, :string, default: "muse"
    field :source_filters, {:array, :string}, default: []
    field :status, :string, default: "draft"
    field :tags, {:array, :string}, default: []
    timestamps()
  end

  def changeset(thought, attrs) do
    thought
    |> cast(attrs, [:question, :answer, :scope, :source_filters, :status, :tags])
    |> validate_required([:question, :scope])
    |> validate_inclusion(:scope, ~w(wonder muse thought))
    |> validate_inclusion(:status, ~w(draft complete saved))
  end
end
