defmodule ExCalibur.Repo.Migrations.RemoveNilStepIdsFromQuests do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE excellence_quests
    SET steps = (
      SELECT array_agg(step)
      FROM unnest(steps) AS step
      WHERE step->>'step_id' IS NOT NULL
    )
    WHERE EXISTS (
      SELECT 1
      FROM unnest(steps) AS step
      WHERE step->>'step_id' IS NULL
    )
    """)
  end

  def down, do: :ok
end
