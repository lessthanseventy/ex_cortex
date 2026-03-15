defmodule ExCortex.Thoughts.Daydream do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "daydreams" do
    field :thought_id, :integer
    field :status, :string, default: "pending"
    field :synapse_results, :map, default: %{}
    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:thought_id, :status, :synapse_results])
    |> validate_required([:thought_id])
    |> validate_inclusion(:status, ["pending", "running", "complete", "failed"])
  end
end
