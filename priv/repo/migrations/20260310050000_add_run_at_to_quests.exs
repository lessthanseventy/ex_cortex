defmodule ExCalibur.Repo.Migrations.AddRunAtToQuests do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      add :run_at, :utc_datetime, null: true
    end
  end
end
