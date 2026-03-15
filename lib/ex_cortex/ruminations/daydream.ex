defmodule ExCortex.Ruminations.Daydream do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "daydreams" do
    field :rumination_id, :integer
    field :status, :string, default: "pending"
    field :synapse_results, :map, default: %{}
    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:rumination_id, :status, :synapse_results])
    |> validate_required([:rumination_id])
    |> validate_inclusion(:status, ["pending", "running", "complete", "failed", "dry_run", "gated"])
  end
end
