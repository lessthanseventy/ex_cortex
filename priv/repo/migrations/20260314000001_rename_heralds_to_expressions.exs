defmodule ExCortex.Repo.Migrations.RenameHeraldsToExpressions do
  use Ecto.Migration

  def change do
    rename table(:herald_channels), to: table(:expressions)
  end
end
