defmodule ExCortex.Repo.Migrations.CreateDictionaries do
  use Ecto.Migration

  def change do
    create table(:dictionaries) do
      add :name, :string, null: false
      add :description, :string
      add :content, :text, default: ""
      add :content_type, :string, default: "text"
      add :tags, {:array, :string}, default: []
      add :filename, :string
      timestamps()
    end

    create unique_index(:dictionaries, [:name])
  end
end
