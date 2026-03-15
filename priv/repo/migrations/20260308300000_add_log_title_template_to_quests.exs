defmodule ExCortex.Repo.Migrations.AddLogTitleTemplateToQuests do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      add :log_title_template, :string
    end
  end
end
