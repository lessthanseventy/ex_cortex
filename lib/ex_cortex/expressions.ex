defmodule ExCortex.Expressions do
  @moduledoc false
  import Ecto.Query

  alias ExCortex.Expressions.Expression
  alias ExCortex.Repo

  def list_expressions, do: Repo.all(from e in Expression, order_by: [asc: e.name])

  def list_by_type(type), do: Repo.all(from e in Expression, where: e.type == ^type, order_by: [asc: e.name])

  def get_by_name(name) do
    case Repo.one(from e in Expression, where: e.name == ^name) do
      nil -> {:error, :not_found}
      e -> {:ok, e}
    end
  end

  def create_expression(attrs), do: %Expression{} |> Expression.changeset(attrs) |> Repo.insert()

  def delete_expression(%Expression{} = e), do: Repo.delete(e)

  def deliver(%Expression{type: type, id: expression_id} = expression, thought, body) do
    provider = provider_module(type)

    case provider.deliver(expression, thought, body) do
      {:ok, external_ref} ->
        create_correlation(expression_id, thought, external_ref)
        {:ok, external_ref}

      :ok ->
        :ok

      error ->
        error
    end
  end

  defp provider_module("slack"), do: ExCortex.Expressions.Slack
  defp provider_module("webhook"), do: ExCortex.Expressions.Webhook
  defp provider_module("github_issue"), do: ExCortex.Expressions.GithubIssue
  defp provider_module("github_pr"), do: ExCortex.Expressions.GithubPR
  defp provider_module("email"), do: ExCortex.Expressions.Email
  defp provider_module("pagerduty"), do: ExCortex.Expressions.PagerDuty

  defp create_correlation(expression_id, thought, external_ref) do
    alias ExCortex.Expressions.Correlation

    attrs = %{
      expression_id: expression_id,
      daydream_id: Map.get(thought, :daydream_id) || Map.get(thought, :id),
      synapse_id: Map.get(thought, :id),
      external_ref: external_ref
    }

    %Correlation{} |> Correlation.changeset(attrs) |> Repo.insert()
  end
end
