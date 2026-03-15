defmodule ExCortex.Repo.Migrations.RenameThoughtsToRuminations do
  use Ecto.Migration

  def change do
    rename table(:thoughts), to: table(:ruminations)
    rename table(:daydreams), :thought_id, to: :rumination_id
    rename table(:engrams), :thought_id, to: :rumination_id
    rename table(:signals), :thought_id, to: :rumination_id
  end
end
