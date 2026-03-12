defmodule ExCalibur.Quests.Proposal do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "excellence_proposals" do
    field :type, :string
    field :description, :string
    field :details, :map, default: %{}
    field :status, :string, default: "pending"
    field :applied_at, :utc_datetime
    field :tool_name, :string
    field :tool_args, :map, default: %{}
    field :context, :string
    field :result, :string

    belongs_to :step, ExCalibur.Quests.Step, foreign_key: :quest_id
    belongs_to :step_run, ExCalibur.Quests.StepRun, foreign_key: :quest_run_id

    timestamps()
  end

  @required [:quest_id, :type, :description]
  @optional [:quest_run_id, :details, :status, :applied_at, :tool_name, :tool_args, :context, :result]

  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["pending", "approved", "rejected", "applied", "executed", "failed"])
    |> validate_inclusion(:type, ["roster_change", "schedule_change", "prompt_change", "other", "tool_action"])
  end
end
