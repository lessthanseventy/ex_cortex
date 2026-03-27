defmodule ExCortex.Repo.Migrations.AddOmcInspiredFeatures do
  use Ecto.Migration

  def change do
    # Feature 5: Bounded pipeline loops
    alter table(:ruminations) do
      add :max_iterations, :integer, default: 1
    end

    alter table(:synapses) do
      add :convergence_verdict, :string
    end

    alter table(:daydreams) do
      add :iteration_count, :integer, default: 1
      # Feature 7: Scratchpad middleware
      add :scratchpad, :map, default: %{}
    end

    # Feature 6: Keyword-triggered ruminations
    alter table(:ruminations) do
      add :keyword_patterns, {:array, :string}, default: []
    end
  end
end
