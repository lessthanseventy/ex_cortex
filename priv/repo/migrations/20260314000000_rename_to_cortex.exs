defmodule ExCortex.Repo.Migrations.RenameToCortex do
  use Ecto.Migration

  def change do
    # Rename existing tables to brain/consciousness vocabulary
    rename table(:excellence_members), to: table(:neurons)
    rename table(:excellence_quests), to: table(:thoughts)
    rename table(:excellence_quest_runs), to: table(:daydreams)
    rename table(:excellence_step_runs), to: table(:impulses)
    rename table(:excellence_steps), to: table(:synapses)
    rename table(:excellence_proposals), to: table(:proposals)
    rename table(:lore_entries), to: table(:engrams)
    rename table(:lodge_cards), to: table(:signals)
    rename table(:lodge_card_versions), to: table(:signal_versions)
    rename table(:guild_charters), to: table(:clusters)
    rename table(:member_trust_scores), to: table(:neuron_trust_scores)
    rename table(:excellence_sources), to: table(:senses)
    rename table(:heralds), to: table(:herald_channels)

    # Rename foreign key columns to match new vocabulary
    rename table(:impulses), :step_id, to: :synapse_id
    rename table(:impulses), :quest_run_id, to: :daydream_id
    rename table(:daydreams), :quest_id, to: :thought_id
    rename table(:engrams), :quest_id, to: :thought_id
    rename table(:signals), :quest_id, to: :thought_id
    rename table(:proposals), :quest_id, to: :synapse_id
    rename table(:proposals), :quest_run_id, to: :daydream_id
    rename table(:daydreams), :step_results, to: :synapse_results

    # Add memory tier fields to engrams
    alter table(:engrams) do
      add :impression, :text
      add :recall, :text
      add :category, :string, default: "semantic"
      add :cluster_name, :string
      add :daydream_id, references(:daydreams, on_delete: :nilify_all)
    end

    # Create recall_paths table
    create table(:recall_paths) do
      add :daydream_id, references(:daydreams, on_delete: :delete_all), null: false
      add :engram_id, references(:engrams, on_delete: :delete_all), null: false
      add :reason, :text
      add :relevance_score, :float
      add :tier_accessed, :string
      add :step, :integer
      timestamps()
    end

    # Indexes
    create index(:engrams, [:category])
    create index(:engrams, [:cluster_name])
    create index(:engrams, [:tags], using: "GIN")
    create index(:recall_paths, [:daydream_id])
    create index(:recall_paths, [:engram_id])
  end
end
