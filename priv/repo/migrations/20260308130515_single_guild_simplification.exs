defmodule ExCellenceServer.Repo.Migrations.SingleGuildSimplification do
  use Ecto.Migration

  def change do
    alter table(:excellence_sources) do
      remove :guild_name, :string
      add :book_id, :string
    end

    drop_if_exists index(:excellence_sources, [:guild_name])
  end
end
