defmodule ExCortex.Repo.Migrations.UpgradeLodgeCards do
  use Ecto.Migration

  def change do
    alter table(:lodge_cards) do
      add :card_type, :string, default: "briefing"
      add :pin_slug, :string
      add :pin_order, :integer, default: 0
      add :guild_name, :string
    end

    create unique_index(:lodge_cards, [:pin_slug], where: "pin_slug IS NOT NULL")

    create table(:lodge_card_versions) do
      add :card_id, references(:lodge_cards, on_delete: :delete_all), null: false
      add :body, :text
      add :metadata, :map, default: %{}
      add :replaced_at, :utc_datetime, null: false
    end

    create index(:lodge_card_versions, [:card_id])
  end
end
