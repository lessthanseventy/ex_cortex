defmodule ExCortex.Repo.Migrations.TextDescriptionsOnQuestsAndCampaigns do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      modify :description, :text
    end

    alter table(:excellence_campaigns) do
      modify :description, :text
    end
  end
end
