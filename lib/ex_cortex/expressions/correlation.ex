defmodule ExCortex.Expressions.Correlation do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "expression_correlations" do
    field :expression_id, :integer
    field :daydream_id, :integer
    field :synapse_id, :integer
    field :external_ref, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(correlation, attrs) do
    correlation
    |> cast(attrs, [:expression_id, :daydream_id, :synapse_id, :external_ref])
    |> validate_required([:expression_id, :daydream_id, :external_ref])
  end
end
