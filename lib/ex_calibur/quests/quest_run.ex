defmodule ExCalibur.Quests.QuestRun do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "excellence_quest_runs" do
    field :quest_id, :integer
    field :status, :string, default: "pending"
    field :step_results, :map, default: %{}
    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:quest_id, :status, :step_results])
    |> validate_required([:quest_id])
    |> validate_inclusion(:status, ["pending", "running", "complete", "failed"])
  end
end
