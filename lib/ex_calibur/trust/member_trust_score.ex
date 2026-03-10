defmodule ExCalibur.Trust.MemberTrustScore do
  use Ecto.Schema
  import Ecto.Changeset

  schema "member_trust_scores" do
    field :member_name, :string
    field :score, :float, default: 1.0
    field :decay_count, :integer, default: 0
    timestamps()
  end

  def changeset(score, attrs) do
    score
    |> cast(attrs, [:member_name, :score, :decay_count])
    |> validate_required([:member_name])
  end
end
