defmodule ExCalibur.Repo.Migrations.AddConfigToSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add :config, :map, default: %{}
    end
  end
end
