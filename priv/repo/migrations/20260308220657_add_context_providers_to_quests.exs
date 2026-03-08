defmodule ExCellenceServer.Repo.Migrations.AddContextProvidersToQuests do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      add :context_providers, {:array, :map}, default: []
    end
  end
end
