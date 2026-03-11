defmodule ExCalibur.Repo.Migrations.CreateLodgeCards do
  use Ecto.Migration

  def change do
    create table(:lodge_cards) do
      add :type, :string, null: false
      add :title, :string, null: false
      add :body, :text, default: ""
      add :metadata, :map, default: %{}
      add :pinned, :boolean, default: false, null: false
      add :source, :string, null: false
      add :quest_id, :integer
      add :status, :string, default: "active", null: false

      timestamps()
    end

    create index(:lodge_cards, [:type])
    create index(:lodge_cards, [:status])
    create index(:lodge_cards, [:quest_id])
    create index(:lodge_cards, [:pinned])
  end
end
