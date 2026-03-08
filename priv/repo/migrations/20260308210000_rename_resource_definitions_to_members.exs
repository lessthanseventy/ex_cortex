defmodule ExCalibur.Repo.Migrations.RenameResourceDefinitionsToMembers do
  use Ecto.Migration

  def change do
    # excellence_resource_definitions was removed; excellence_members is created directly in add_excellence_tables
  end
end
