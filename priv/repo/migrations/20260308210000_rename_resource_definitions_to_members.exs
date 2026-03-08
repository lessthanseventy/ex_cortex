defmodule ExCellenceServer.Repo.Migrations.RenameResourceDefinitionsToMembers do
  use Ecto.Migration

  def change do
    rename table(:excellence_resource_definitions), to: table(:excellence_members)
  end
end
