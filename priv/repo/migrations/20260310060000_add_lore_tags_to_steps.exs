defmodule ExCortex.Repo.Migrations.AddLoreTagsToSteps do
  use Ecto.Migration

  def change do
    alter table(:excellence_steps) do
      add :lore_tags, {:array, :string}, default: []
    end
  end
end
