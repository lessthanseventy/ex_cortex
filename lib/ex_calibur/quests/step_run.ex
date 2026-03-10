defmodule ExCalibur.Quests.StepRun do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "excellence_step_runs" do
    field :step_id, :integer
    field :quest_run_id, :integer
    field :input, :string
    field :status, :string, default: "pending"
    field :results, :map, default: %{}
    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:step_id, :quest_run_id, :input, :status, :results])
    |> validate_required([:step_id])
    |> validate_inclusion(:status, ["pending", "running", "complete", "failed"])
  end
end
