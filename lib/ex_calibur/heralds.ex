defmodule ExCalibur.Heralds do
  @moduledoc false
  import Ecto.Query

  alias ExCalibur.Heralds.Herald
  alias ExCalibur.Repo

  def list_heralds, do: Repo.all(from h in Herald, order_by: [asc: h.name])

  def list_by_type(type), do: Repo.all(from h in Herald, where: h.type == ^type, order_by: [asc: h.name])

  def get_by_name(name) do
    case Repo.one(from h in Herald, where: h.name == ^name) do
      nil -> {:error, :not_found}
      h -> {:ok, h}
    end
  end

  def create_herald(attrs), do: %Herald{} |> Herald.changeset(attrs) |> Repo.insert()

  def delete_herald(%Herald{} = h), do: Repo.delete(h)

  def deliver(%Herald{type: "slack"} = h, quest, body),
    do: ExCalibur.Heralds.Slack.deliver(h, quest, body)

  def deliver(%Herald{type: "webhook"} = h, quest, body),
    do: ExCalibur.Heralds.Webhook.deliver(h, quest, body)

  def deliver(%Herald{type: "github_issue"} = h, quest, body),
    do: ExCalibur.Heralds.GithubIssue.deliver(h, quest, body)

  def deliver(%Herald{type: "github_pr"} = h, quest, body),
    do: ExCalibur.Heralds.GithubPR.deliver(h, quest, body)

  def deliver(%Herald{type: "email"} = h, quest, body),
    do: ExCalibur.Heralds.Email.deliver(h, quest, body)

  def deliver(%Herald{type: "pagerduty"} = h, quest, body),
    do: ExCalibur.Heralds.PagerDuty.deliver(h, quest, body)
end
