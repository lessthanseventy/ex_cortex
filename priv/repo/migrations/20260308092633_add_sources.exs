defmodule ExCalibur.Repo.Migrations.AddSources do
  use Ecto.Migration

  def change do
    create table(:excellence_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :guild_name, :string, null: false
      add :source_type, :string, null: false
      add :config, :map, null: false, default: %{}
      add :state, :map, null: false, default: %{}
      add :status, :string, null: false, default: "active"
      add :last_run_at, :utc_datetime
      add :error_message, :string
      timestamps(type: :utc_datetime)
    end

    create index(:excellence_sources, [:guild_name])
    create index(:excellence_sources, [:status])
  end
end
