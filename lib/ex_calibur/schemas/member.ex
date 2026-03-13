defmodule ExCalibur.Schemas.Member do
  @moduledoc "Agent role/resource definition stored in the database."
  use Ecto.Schema

  import Ecto.Changeset

  @valid_types ~w(role actions guard escalation outcome dimensions profile)
  @valid_statuses ~w(draft shadow active paused archived)
  @valid_sources ~w(code db frozen)

  schema "excellence_members" do
    field :type, :string
    field :name, :string
    field :status, :string, default: "draft"
    field :config, :map, default: %{}
    field :source, :string, default: "db"
    field :version, :integer, default: 1
    field :created_by, :string
    field :team, :string
    timestamps()
  end

  def changeset(definition, attrs) do
    definition
    |> cast(attrs, [:type, :name, :status, :config, :source, :version, :created_by, :team])
    |> validate_required([:type, :name])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:source, @valid_sources)
    |> maybe_bump_version()
  end

  defp maybe_bump_version(%{data: %{version: v}} = changeset) when is_integer(v) and v > 0 do
    put_change(changeset, :version, v + 1)
  end

  defp maybe_bump_version(changeset), do: changeset
end
