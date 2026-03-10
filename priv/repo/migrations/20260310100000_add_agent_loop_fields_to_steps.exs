defmodule ExCalibur.Repo.Migrations.AddAgentLoopFieldsToSteps do
  use Ecto.Migration

  def change do
    alter table(:excellence_steps) do
      add :escalate, :boolean, default: false, null: false
      add :escalate_threshold, :float, default: 0.6
      add :escalate_on_verdict, {:array, :string}, default: []
      add :loop_mode, :string
      add :loop_tools, {:array, :string}, default: []
      add :reflect_threshold, :float, default: 0.6
      add :reflect_on_verdict, {:array, :string}, default: []
      add :max_iterations, :integer, default: 3
    end
  end
end
