defmodule ExCalibur.Quests.Campaign do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "excellence_campaigns" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "active"
    field :trigger, :string, default: "manual"
    field :schedule, :string
    field :steps, {:array, :map}, default: []
    field :source_ids, {:array, :string}, default: []
    timestamps()
  end

  @required [:name, :trigger]
  @optional [:description, :status, :schedule, :steps, :source_ids]

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["active", "paused"])
    |> validate_inclusion(:trigger, ["manual", "source", "scheduled"])
    |> unique_constraint(:name)
  end
end
