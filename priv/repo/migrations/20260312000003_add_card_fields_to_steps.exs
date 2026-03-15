defmodule ExCortex.Repo.Migrations.AddCardFieldsToSteps do
  use Ecto.Migration

  def change do
    alter table(:excellence_steps) do
      add :pin_slug, :string
      add :pin_order, :integer, default: 0
      add :cards, :map, default: %{}
      add :guild_name, :string
    end
  end
end
