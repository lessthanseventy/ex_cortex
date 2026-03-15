defmodule ExCortex.Repo.Migrations.AddStepGuardrailFields do
  use Ecto.Migration

  def change do
    alter table(:excellence_steps) do
      add :dangerous_tool_mode, :string, default: "execute"
      add :max_tool_iterations, :integer, default: 15
    end
  end
end
