defmodule ExCalibur.Repo.Migrations.AddQuestsAndCampaigns do
  use Ecto.Migration

  def change do
    create table(:excellence_quests) do
      add :name, :string, null: false
      add :description, :string
      add :status, :string, null: false, default: "active"
      add :trigger, :string, null: false, default: "manual"
      add :schedule, :string
      add :roster, {:array, :map}, default: []
      add :source_ids, {:array, :string}, default: []
      timestamps()
    end

    create unique_index(:excellence_quests, [:name])

    create table(:excellence_quest_runs) do
      add :quest_id, references(:excellence_quests, on_delete: :delete_all)
      add :campaign_run_id, :integer
      add :input, :text
      add :status, :string, null: false, default: "pending"
      add :results, :map, default: %{}
      timestamps()
    end

    create index(:excellence_quest_runs, [:quest_id])
    create index(:excellence_quest_runs, [:campaign_run_id])

    create table(:excellence_campaigns) do
      add :name, :string, null: false
      add :description, :string
      add :status, :string, null: false, default: "active"
      add :trigger, :string, null: false, default: "manual"
      add :schedule, :string
      add :steps, {:array, :map}, default: []
      add :source_ids, {:array, :string}, default: []
      timestamps()
    end

    create unique_index(:excellence_campaigns, [:name])

    create table(:excellence_campaign_runs) do
      add :campaign_id, references(:excellence_campaigns, on_delete: :delete_all)
      add :status, :string, null: false, default: "pending"
      add :step_results, :map, default: %{}
      timestamps()
    end

    create index(:excellence_campaign_runs, [:campaign_id])
  end
end
