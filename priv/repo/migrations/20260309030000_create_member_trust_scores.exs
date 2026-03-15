defmodule ExCortex.Repo.Migrations.CreateMemberTrustScores do
  use Ecto.Migration

  def change do
    create table(:member_trust_scores) do
      add :member_name, :string, null: false
      add :score, :float, null: false, default: 1.0
      add :decay_count, :integer, null: false, default: 0
      timestamps()
    end

    create unique_index(:member_trust_scores, [:member_name])
  end
end
