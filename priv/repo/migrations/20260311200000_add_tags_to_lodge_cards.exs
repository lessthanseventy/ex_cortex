defmodule ExCortex.Repo.Migrations.AddTagsToLodgeCards do
  use Ecto.Migration

  def change do
    alter table(:lodge_cards) do
      add :tags, {:array, :string}, default: [], null: false
    end

    create index(:lodge_cards, [:tags], using: :gin)
  end
end
