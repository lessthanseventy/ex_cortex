defmodule ExCortex.Senses.GithubIssueWatcher do
  @moduledoc "Polls GitHub for issues with a specific label."
  @behaviour ExCortex.Senses.Behaviour

  alias ExCortex.Senses.Item

  require Logger

  @impl true
  def init(config) do
    repo = config["repo"]

    if is_nil(repo) or repo == "" do
      {:error, "repo is required (owner/repo format)"}
    else
      {:ok, %{seen_ids: config["seen_ids"] || []}}
    end
  end

  @impl true
  def fetch(state, config) do
    repo = config["repo"]
    label = config["label"] || "self-improvement"

    args = [
      "issue",
      "list",
      "--repo",
      repo,
      "--label",
      label,
      "--state",
      "open",
      "--json",
      "number,title,body,labels,createdAt",
      "--limit",
      "10"
    ]

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} ->
        issues = Jason.decode!(output)
        new_issues = Enum.reject(issues, &(&1["number"] in state.seen_ids))

        items =
          Enum.map(new_issues, fn issue ->
            %Item{
              source_id: config["source_id"],
              type: "github_issue",
              content: "## Issue ##{issue["number"]}: #{issue["title"]}\n\n#{issue["body"] || ""}",
              metadata: %{
                number: issue["number"],
                title: issue["title"],
                labels: Enum.map(issue["labels"] || [], & &1["name"])
              }
            }
          end)

        new_seen = state.seen_ids ++ Enum.map(new_issues, & &1["number"])
        {:ok, items, %{state | seen_ids: new_seen}}

      {error, _} ->
        Logger.warning("[GithubIssueWatcher] gh command failed: #{error}")
        {:error, error}
    end
  end
end
