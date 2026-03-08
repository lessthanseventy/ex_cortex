defmodule ExCellenceServer.Quests.Quest do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "excellence_quests" do
    field :name, :string
    field :description, :string
    field :status, :string
    field :trigger, :string
    field :schedule, :string
    field :roster, {:array, :map}, default: []
    field :source_ids, {:array, :string}, default: []
    timestamps()
  end

  @required [:name, :trigger]
  @optional [:description, :status, :schedule, :roster, :source_ids]

  def changeset(quest, attrs) do
    quest
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["active", "paused"])
    |> validate_inclusion(:trigger, ["manual", "source", "scheduled"])
    |> unique_constraint(:name)
  end
end
