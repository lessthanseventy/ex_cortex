defmodule ExCortex.Repo.Migrations.AddMiddlewareAndDedupFields do
  use Ecto.Migration

  def change do
    alter table(:synapses) do
      add :middleware, {:array, :string}, default: []
    end

    alter table(:ruminations) do
      add :dedup_strategy, :string, default: "none"
    end

    alter table(:daydreams) do
      add :fingerprint, :string
    end

    create index(:daydreams, [:fingerprint])

    alter table(:senses) do
      add :trust_level, :string, default: "untrusted"
    end
  end
end
