defmodule ExCalibur.Repo.Migrations.UpgradeProposals do
  use Ecto.Migration

  def change do
    alter table(:excellence_proposals) do
      add :tool_name, :string
      add :tool_args, :map, default: %{}
      add :context, :text
      add :result, :text
    end
  end
end
