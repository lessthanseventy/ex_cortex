defmodule ExCortex.Tools.SearchGithub do
  @moduledoc "Tool: search GitHub issues, PRs, or repos via gh CLI."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "search_github",
      description:
        "Search GitHub issues, pull requests, or repositories using the gh CLI. Use `label` to filter issues by label (e.g. 'self-improvement') — this is more reliable than text search for label-based lookups.",
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
    repo = ExCortex.Settings.get(:default_repo)

    args = build_args(type, query, limit, repo, label)

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  defp build_args("repos", query, limit, _repo, _label) do
    ["search", "repos", query, "--limit", to_string(limit), "--json", "name,fullName,description,url,stargazersCount"]
  end

  defp build_args("prs", query, limit, repo, _label) do
    clean = strip_repo_incompatible_qualifiers(query)
    base = ["search", "prs", clean, "--limit", to_string(limit), "--json", "number,title,state,url"]
    if repo, do: base ++ ["--repo", repo], else: base
  end

  # When a label is given, use `gh issue list --label` (searches label index, not full text)
  defp build_args(_issues, _query, limit, repo, label) when is_binary(label) and label != "" do
    base = [
      "issue",
      "list",
      "--label",
      label,
      "--state",
      "open",
      "--limit",
      to_string(limit),
      "--json",
      "number,title,state,url"
    ]

    if repo, do: base ++ ["--repo", repo], else: base
  end

  defp build_args(_issues, query, limit, repo, _label) do
    clean = strip_repo_incompatible_qualifiers(query)
    base = ["search", "issues", clean, "--limit", to_string(limit), "--json", "number,title,state,url"]
    if repo, do: base ++ ["--repo", repo, "--state", "open"], else: base
  end

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
