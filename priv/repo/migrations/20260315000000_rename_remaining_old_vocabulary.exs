defmodule ExCortex.Repo.Migrations.RenameRemainingOldVocabulary do
  use Ecto.Migration

  def change do
    # Rename remaining old-vocabulary columns to brain vocabulary

    # clusters
    rename table(:clusters), :guild_name, to: :cluster_name
    rename table(:clusters), :charter_text, to: :pathway_text

    # synapses
    rename table(:synapses), :herald_name, to: :expression_name
    rename table(:synapses), :lore_tags, to: :engram_tags
    rename table(:synapses), :guild_name, to: :cluster_name

    # thoughts
    rename table(:thoughts), :lore_trigger_tags, to: :engram_trigger_tags
    rename table(:thoughts), :lodge_trigger_types, to: :signal_trigger_types
    rename table(:thoughts), :lodge_trigger_tags, to: :signal_trigger_tags

    # signals
    rename table(:signals), :guild_name, to: :cluster_name

    # senses
    rename table(:senses), :book_id, to: :reflex_id

    # neuron_trust_scores
    rename table(:neuron_trust_scores), :member_name, to: :neuron_name

    # dictionaries → axioms
    rename table(:dictionaries), to: table(:axioms)
  end
end
