defmodule ExCalibur.Repo.Migrations.CreateLoreEntries do
  use Ecto.Migration

  def change do
    create table(:lore_entries) do
      add :quest_id, :integer
      add :title, :string, null: false
      add :body, :text, default: ""
      add :tags, {:array, :string}, default: []
      add :importance, :integer
      add :source, :string, default: "quest"
      timestamps()
    end

    create index(:lore_entries, [:quest_id])
    create index(:lore_entries, [:source])
  end
end
