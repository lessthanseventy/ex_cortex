defmodule ExCortex.Memory.RecallPath do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "recall_paths" do
    belongs_to :daydream, ExCortex.Ruminations.Daydream
    belongs_to :engram, ExCortex.Memory.Engram

    field :reason, :string
    field :relevance_score, :float
    field :tier_accessed, :string
    field :step, :integer

    timestamps()
  end

  @required [:daydream_id, :engram_id]
  @optional [:reason, :relevance_score, :tier_accessed, :step]

  def changeset(recall_path, attrs) do
    recall_path
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:tier_accessed, ~w(L0 L1 L2))
  end
end
