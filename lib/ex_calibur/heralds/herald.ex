defmodule ExCalibur.Heralds.Herald do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @herald_types ~w(slack webhook github_issue github_pr email pagerduty)

  schema "heralds" do
    field :name, :string
    field :type, :string
    field :config, :map, default: %{}
    timestamps()
  end

  def changeset(herald, attrs) do
    herald
    |> cast(attrs, [:name, :type, :config])
    |> validate_required([:name, :type])
    |> validate_inclusion(:type, @herald_types)
    |> unique_constraint(:name)
  end
end
