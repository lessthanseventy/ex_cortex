defmodule ExCalibur.Repo.Migrations.CreateProposals do
  use Ecto.Migration

  def change do
    create table(:excellence_proposals) do
      add :quest_id, references(:excellence_quests, on_delete: :delete_all), null: false
      add :quest_run_id, references(:excellence_quest_runs, on_delete: :nilify_all)
      add :type, :string, null: false
      add :description, :text, null: false
      add :details, :map, default: %{}
      add :status, :string, default: "pending", null: false
      add :applied_at, :utc_datetime

      timestamps()
    end

    create index(:excellence_proposals, [:quest_id])
    create index(:excellence_proposals, [:status])
  end
end
