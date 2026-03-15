defmodule ExCortex.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings) do
      add :banner, :string

      timestamps()
    end
  end
end
