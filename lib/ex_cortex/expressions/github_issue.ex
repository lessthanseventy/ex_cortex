defmodule ExCortex.Expressions.GithubIssue do
  @moduledoc "Opens a GitHub issue with thought output as body."

  def deliver(%{config: config}, _thought, body) do
    token = config["token"] || raise "GitHub expression missing token"
    owner = config["owner"] || raise "GitHub expression missing owner"
    repo = config["repo"] || raise "GitHub expression missing repo"

    url = "https://api.github.com/repos/#{owner}/#{repo}/issues"
    labels = body.tags || []

    payload = %{title: body.title, body: body.body, labels: labels}

    case Req.post(url,
           json: payload,
           auth: {:bearer, token},
           headers: [{"Accept", "application/vnd.github+json"}, {"X-GitHub-Api-Version", "2022-11-28"}]
         ) do
      {:ok, %{status: 201}} -> :ok
      {:ok, resp} -> {:error, {:bad_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
