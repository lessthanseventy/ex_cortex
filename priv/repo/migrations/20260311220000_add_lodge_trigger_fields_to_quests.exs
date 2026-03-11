defmodule ExCalibur.Repo.Migrations.AddLodgeTriggerFieldsToQuests do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      add :lodge_trigger_types, {:array, :string}, default: []
      add :lodge_trigger_tags, {:array, :string}, default: []
    end
  end
end
