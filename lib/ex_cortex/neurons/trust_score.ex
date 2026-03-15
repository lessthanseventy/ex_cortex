defmodule ExCortex.Neurons.TrustScore do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "neuron_trust_scores" do
    field :neuron_name, :string
    field :score, :float, default: 1.0
    field :decay_count, :integer, default: 0
    timestamps()
  end

  def changeset(score, attrs) do
    score
    |> cast(attrs, [:neuron_name, :score, :decay_count])
    |> validate_required([:neuron_name])
  end
end
