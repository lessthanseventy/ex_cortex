defmodule ExCortex.Expressions.Expression do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @expression_types ~w(slack webhook github_issue github_pr email pagerduty)

  schema "expressions" do
    field :name, :string
    field :type, :string
    field :config, :map, default: %{}
    timestamps()
  end

  def changeset(expression, attrs) do
    expression
    |> cast(attrs, [:name, :type, :config])
    |> validate_required([:name, :type])
    |> validate_inclusion(:type, @expression_types)
    |> unique_constraint(:name)
  end
end
