defmodule ExCalibur.Repo.Migrations.AddMinRankToQuests do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      add :min_rank, :string, null: true
    end
  end
end
