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

    args = build_args(type, query, limit)

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  defp build_args("repos", query, limit) do
    ["search", "repos", query, "--limit", to_string(limit), "--json", "name,fullName,description,url,stargazersCount"]
  end

  defp build_args("prs", query, limit) do
    ["search", "prs", query, "--limit", to_string(limit), "--json", "number,title,state,url"]
  end

  defp build_args(_issues, query, limit) do
    ["search", "issues", query, "--limit", to_string(limit), "--json", "number,title,state,url"]
  end
end
