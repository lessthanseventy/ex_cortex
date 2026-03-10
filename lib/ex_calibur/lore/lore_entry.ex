defmodule ExCalibur.Lore.LoreEntry do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "lore_entries" do
    field :quest_id, :integer
    field :title, :string
    field :body, :string, default: ""
    field :tags, {:array, :string}, default: []
    field :importance, :integer
    field :source, :string, default: "quest"
    timestamps()
  end

  @required [:title]
  @optional [:quest_id, :body, :tags, :importance, :source]

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:source, ["quest", "manual"])
    |> validate_number(:importance, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
  end
end
