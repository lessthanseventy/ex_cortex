defmodule ExCortex.Thoughts.Impulse do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "impulses" do
    field :synapse_id, :integer
    field :daydream_id, :integer
    field :input, :string
    field :status, :string, default: "pending"
    field :results, :map, default: %{}
    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:synapse_id, :daydream_id, :input, :status, :results])
    |> validate_required([:synapse_id])
    |> validate_inclusion(:status, ["pending", "running", "complete", "failed"])
  end
end
