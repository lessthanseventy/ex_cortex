defmodule ExCortex.Repo.Migrations.CreateHeralds do
  use Ecto.Migration

  def change do
    create table(:heralds) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :config, :map, default: %{}
      timestamps()
    end

    create unique_index(:heralds, [:name])
  end
end
