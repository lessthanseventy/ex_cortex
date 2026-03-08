defmodule ExCalibur.Quests.CampaignRun do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "excellence_campaign_runs" do
    field :campaign_id, :integer
    field :status, :string, default: "pending"
    field :step_results, :map, default: %{}
    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:campaign_id, :status, :step_results])
    |> validate_required([:campaign_id])
    |> validate_inclusion(:status, ["pending", "running", "complete", "failed"])
  end
end
