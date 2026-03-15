defmodule ExCortex.ContextProviders.GithubIssues do
  @moduledoc """
  Fetches open GitHub issues by label and injects them as prompt context.

  The model receives the issue list directly — no search_github tool call needed.

  Config:
    "label"  - issue label to filter by (default: "self-improvement")
    "limit"  - max issues to fetch (default: 20)
    "header" - optional section header

  Example:
    %{"type" => "github_issues", "label" => "self-improvement"}
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  require Logger

  @impl true
  def build(config, _thought, _input) do
    label = Map.get(config, "label", "self-improvement")
    limit = Map.get(config, "limit", 20)
    header = Map.get(config, "header", "## Open GitHub Issues (label: #{label})")
    repo = ExCortex.Settings.get(:default_repo)

    args =
      then(
        [
          "issue",
          "list",
          "--label",
          label,
          "--state",
          "open",
          "--limit",
          to_string(limit),
          "--json",
          "number,title,state,url,body"
        ],
        fn base -> if repo, do: base ++ ["--repo", repo], else: base end
      )

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, []} ->
            "#{header}\n\nNo open issues with label '#{label}'."

          {:ok, issues} ->
            lines =
              Enum.map(issues, fn issue ->
                "##{issue["number"]}: #{issue["title"]}\n#{issue["url"]}"
              end)

            "#{header}\n\n#{Enum.join(lines, "\n\n")}"

          {:error, _} ->
            Logger.warning("[GithubIssuesCtx] Could not parse gh output")
            ""
        end

      {error, _} ->
        Logger.warning("[GithubIssuesCtx] gh command failed: #{String.slice(error, 0, 200)}")
        "#{header}\n\n(Could not fetch issues: gh CLI not available or not configured)"
    end
  end
end
