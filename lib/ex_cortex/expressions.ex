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

  def deliver(%Expression{type: "slack"} = e, thought, body), do: ExCortex.Expressions.Slack.deliver(e, thought, body)
  def deliver(%Expression{type: "webhook"} = e, thought, body), do: ExCortex.Expressions.Webhook.deliver(e, thought, body)

  def deliver(%Expression{type: "github_issue"} = e, thought, body),
    do: ExCortex.Expressions.GithubIssue.deliver(e, thought, body)

  def deliver(%Expression{type: "github_pr"} = e, thought, body),
    do: ExCortex.Expressions.GithubPR.deliver(e, thought, body)

  def deliver(%Expression{type: "email"} = e, thought, body), do: ExCortex.Expressions.Email.deliver(e, thought, body)

  def deliver(%Expression{type: "pagerduty"} = e, thought, body),
    do: ExCortex.Expressions.PagerDuty.deliver(e, thought, body)
end
