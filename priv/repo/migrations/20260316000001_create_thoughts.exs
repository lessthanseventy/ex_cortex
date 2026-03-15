defmodule ExCortex.Repo.Migrations.CreateThoughts do
  use Ecto.Migration

  def change do
    create table(:thoughts) do
      add :question, :text, null: false
      add :answer, :text
      add :scope, :string, null: false, default: "muse"
      add :source_filters, {:array, :string}, default: []
      add :status, :string, null: false, default: "draft"
      add :tags, {:array, :string}, default: []
      timestamps()
    end

    create index(:thoughts, [:scope])
    create index(:thoughts, [:status])
  end
end
