defmodule ExCalibur.Repo.Migrations.AddArtifactFieldsToQuests do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      add :output_type, :string, default: "verdict"
      add :write_mode, :string, default: "append"
      add :entry_title_template, :string
    end
  end
end
