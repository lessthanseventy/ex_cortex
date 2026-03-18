defmodule ExCortex.Repo.Migrations.CreateExpressionCorrelations do
  use Ecto.Migration

  def change do
    create table(:expression_correlations) do
      add :expression_id, references(:expressions, on_delete: :delete_all)
      add :daydream_id, references(:daydreams, on_delete: :delete_all)
      add :synapse_id, references(:synapses, on_delete: :nilify_all)
      add :external_ref, :string
      timestamps(type: :utc_datetime)
    end

    create index(:expression_correlations, [:external_ref])
    create index(:expression_correlations, [:daydream_id])
  end
end
