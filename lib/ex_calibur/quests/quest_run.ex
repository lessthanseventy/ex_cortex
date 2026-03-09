defmodule ExCalibur.Quests.QuestRun do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "excellence_quest_runs" do
    field :quest_id, :integer
    field :campaign_run_id, :integer
    field :input, :string
    field :status, :string, default: "pending"
    field :results, :map, default: %{}
    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:quest_id, :campaign_run_id, :input, :status, :results])
    |> validate_required([:quest_id])
    |> validate_inclusion(:status, ["pending", "running", "complete", "failed"])
  end
end
