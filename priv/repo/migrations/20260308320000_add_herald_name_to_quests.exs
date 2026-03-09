defmodule ExCalibur.Repo.Migrations.AddHeraldNameToQuests do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      add :herald_name, :string
    end
  end
end
