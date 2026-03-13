defmodule ExCalibur.Tools.SearchGithub do
  @moduledoc "Tool: search GitHub issues, PRs, or repos via gh CLI."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "search_github",
      description: "Search GitHub issues, pull requests, or repositories using the gh CLI.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "Search query string"},
          "type" => %{
            "type" => "string",
            "description" => "What to search: 'issues', 'prs', or 'repos' (default: 'issues')",
            "enum" => ["issues", "prs", "repos"]
          },
          "limit" => %{"type" => "integer", "description" => "Maximum results to return (default 20)"}
        },
        "required" => ["query"]
      },
      callback: &call/1
    )
  end

  def call(%{"query" => query} = params) do
    type = Map.get(params, "type", "issues")
    limit = Map.get(params, "limit", 20)
    repo = ExCalibur.Settings.get(:default_repo)

    args = build_args(type, query, limit, repo)

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  defp build_args("repos", query, limit, _repo) do
    ["search", "repos", query, "--limit", to_string(limit), "--json", "name,fullName,description,url,stargazersCount"]
  end

  defp build_args("prs", query, limit, repo) do
    clean = strip_repo_incompatible_qualifiers(query)
    base = ["search", "prs", clean, "--limit", to_string(limit), "--json", "number,title,state,url"]
    if repo, do: base ++ ["--repo", repo], else: base
  end

  defp build_args(_issues, query, limit, repo) do
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
