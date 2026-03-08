defmodule ExCellenceServer.Repo.Migrations.FlattenMemberRanks do
  use Ecto.Migration

  def change do
    # Members can now exist at multiple ranks — drop unique constraint on (type, name)
    drop_if_exists unique_index(:excellence_members, [:type, :name])
  end
end
