defmodule ExCellenceServer.Repo.Migrations.AddTeamToMembers do
  use Ecto.Migration

  def change do
    alter table(:excellence_members) do
      add :team, :string
    end
  end
end
