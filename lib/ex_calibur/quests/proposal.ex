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

    belongs_to :quest, ExCalibur.Quests.Quest
    belongs_to :quest_run, ExCalibur.Quests.QuestRun

    timestamps()
  end

  @required [:quest_id, :type, :description]
  @optional [:quest_run_id, :details, :status, :applied_at]

  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["pending", "approved", "rejected", "applied"])
    |> validate_inclusion(:type, ["roster_change", "schedule_change", "prompt_change", "other"])
  end
end
