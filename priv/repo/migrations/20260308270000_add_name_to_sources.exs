defmodule ExCalibur.Repo.Migrations.AddNameToSources do
  use Ecto.Migration

  def change do
    alter table(:excellence_sources) do
      add :name, :string
    end
  end
end
