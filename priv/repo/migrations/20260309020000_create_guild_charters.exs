defmodule ExCortex.Repo.Migrations.CreateGuildCharters do
  use Ecto.Migration

  def change do
    create table(:guild_charters) do
      add :guild_name, :string, null: false
      add :charter_text, :text, null: false, default: ""
      timestamps()
    end

    create unique_index(:guild_charters, [:guild_name])
  end
end
