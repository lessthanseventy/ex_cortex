defmodule ExCortex.Repo.Migrations.AddPgvectorAndEmbeddings do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector"

    alter table(:engrams) do
      add :embedding, :vector, size: 768
    end

    execute "CREATE INDEX engrams_embedding_idx ON engrams USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)",
            "DROP INDEX IF EXISTS engrams_embedding_idx"
  end
end
