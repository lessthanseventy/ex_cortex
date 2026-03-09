defmodule ExCalibur.Heralds.GithubPR do
  @moduledoc "Creates a branch, commits quest output as a markdown file, and opens a PR."

  def deliver(%{config: config}, quest, body) do
    token = config["token"] || raise "GitHub herald missing token"
    owner = config["owner"] || raise "GitHub herald missing owner"
    repo = config["repo"] || raise "GitHub herald missing repo"
    base = config["base_branch"] || "main"

    date = Calendar.strftime(Date.utc_today(), "%Y-%m-%d")
    slug = quest.name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
    branch = "herald/#{slug}-#{date}"
    file_path = config["file_path"] || "docs/herald/#{slug}-#{date}.md"
    content = Base.encode64("# #{body.title}\n\n#{body.body}")

    headers = [
      {"Accept", "application/vnd.github+json"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]

    with {:ok, sha} <- get_latest_sha(token, owner, repo, base, headers),
         :ok <- create_branch(token, owner, repo, branch, sha, headers),
         :ok <- create_file(token, owner, repo, branch, file_path, content, body.title, headers),
         {:ok, _} <- create_pr(token, owner, repo, branch, base, body, headers) do
      :ok
    end
  end

  defp get_latest_sha(token, owner, repo, branch, headers) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/git/ref/heads/#{branch}"

    case Req.get(url, auth: {:bearer, token}, headers: headers) do
      {:ok, %{status: 200, body: %{"object" => %{"sha" => sha}}}} -> {:ok, sha}
      {:ok, resp} -> {:error, {:bad_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_branch(token, owner, repo, branch, sha, headers) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/git/refs"

    case Req.post(url,
           json: %{ref: "refs/heads/#{branch}", sha: sha},
           auth: {:bearer, token},
           headers: headers
         ) do
      {:ok, %{status: 201}} -> :ok
      {:ok, resp} -> {:error, {:bad_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_file(token, owner, repo, branch, path, content, message, headers) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/contents/#{path}"

    case Req.put(url,
           json: %{message: message, content: content, branch: branch},
           auth: {:bearer, token},
           headers: headers
         ) do
      {:ok, %{status: s}} when s in [200, 201] -> :ok
      {:ok, resp} -> {:error, {:bad_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_pr(token, owner, repo, branch, base, body, headers) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/pulls"

    case Req.post(url,
           json: %{title: body.title, body: body.body, head: branch, base: base},
           auth: {:bearer, token},
           headers: headers
         ) do
      {:ok, %{status: 201, body: pr}} -> {:ok, pr}
      {:ok, resp} -> {:error, {:bad_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
