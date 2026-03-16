defmodule ExCortex.Tools.SearchGithub do
  @moduledoc "Tool: search GitHub issues, PRs, or repos via gh CLI."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "search_github",
      description: """
      Search GitHub issues, pull requests, or repositories using the gh CLI.

      Use `label` to filter issues by label — more reliable than text search for label-based lookups.
      Use `state` to filter by open/closed/all (default: open).
      Use `assignee` to filter issues/PRs assigned to a specific GitHub user.

      Examples:
      - Find open self-improvement issues: `{"label": "self-improvement"}`
      - Find all closed bugs: `{"label": "bug", "state": "closed"}`
      - Find issues assigned to a user: `{"query": "refactor", "assignee": "octocat"}`
      - Search PRs: `{"query": "fix auth", "type": "prs"}`
      - Search repos: `{"query": "elixir phoenix", "type": "repos"}`
      """,
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "Search query string"},
          "type" => %{
            "type" => "string",
            "description" => "What to search: 'issues', 'prs', or 'repos' (default: 'issues')",
            "enum" => ["issues", "prs", "repos"]
          },
          "label" => %{
            "type" => "string",
            "description" => "Filter issues by label (uses gh issue list, more reliable than text search for labels)"
          },
          "state" => %{
            "type" => "string",
            "description" => "Filter by state (default: 'open')",
            "enum" => ["open", "closed", "all"]
          },
          "assignee" => %{
            "type" => "string",
            "description" => "Filter issues/PRs by assigned GitHub username"
          },
          "limit" => %{"type" => "integer", "description" => "Maximum results to return (default 20)"}
        },
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(params) do
    query = Map.get(params, "query", "")
    type = Map.get(params, "type", "issues")
    limit = Map.get(params, "limit", 20)
    label = Map.get(params, "label")
    state = Map.get(params, "state", "open")
    assignee = Map.get(params, "assignee")
    repo = ExCortex.Settings.get(:default_repo)

    args = build_args(type, query, limit, repo, label, state, assignee)

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  defp build_args("repos", query, limit, _repo, _label, _state, _assignee) do
    ["search", "repos", query, "--limit", to_string(limit), "--json", "name,fullName,description,url,stargazersCount"]
  end

  defp build_args("prs", query, limit, repo, _label, state, assignee) do
    clean = strip_repo_incompatible_qualifiers(query)
    base = ["search", "prs", clean, "--limit", to_string(limit), "--json", "number,title,state,url", "--state", state]
    base = if repo, do: base ++ ["--repo", repo], else: base
    maybe_add_assignee(base, assignee)
  end

  # When a label is given, use `gh issue list --label` (searches label index, not full text)
  defp build_args(_issues, _query, limit, repo, label, state, assignee) when is_binary(label) and label != "" do
    base = [
      "issue",
      "list",
      "--label",
      label,
      "--state",
      state,
      "--limit",
      to_string(limit),
      "--json",
      "number,title,state,url"
    ]

    base = if repo, do: base ++ ["--repo", repo], else: base
    maybe_add_assignee(base, assignee)
  end

  defp build_args(_issues, query, limit, repo, _label, state, assignee) do
    clean = strip_repo_incompatible_qualifiers(query)
    base = ["search", "issues", clean, "--limit", to_string(limit), "--json", "number,title,state,url", "--state", state]
    base = if repo, do: base ++ ["--repo", repo], else: base
    maybe_add_assignee(base, assignee)
  end

  defp maybe_add_assignee(args, nil), do: args
  defp maybe_add_assignee(args, ""), do: args
  defp maybe_add_assignee(args, assignee), do: args ++ ["--assignee", assignee]

  # gh search issues/prs --repo does not support is: qualifiers; strip them
  @incompatible ~w(is:issue is:pr is:open is:closed is:merged is:unmerged)
  defp strip_repo_incompatible_qualifiers(query) do
    query
    |> String.split()
    |> Enum.reject(&(&1 in @incompatible))
    |> Enum.join(" ")
    |> String.trim()
  end
end
