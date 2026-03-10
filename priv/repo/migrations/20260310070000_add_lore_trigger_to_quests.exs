defmodule ExCalibur.Repo.Migrations.AddLoreTriggerToQuests do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      add :lore_trigger_tags, {:array, :string}, default: []
    end
  end
end
