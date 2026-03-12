defmodule ExCalibur.Tools.ReadGithubIssue do
  @moduledoc "Tool: read a GitHub issue or PR by number via gh CLI."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "read_github_issue",
      description: "Read a GitHub issue or PR by number, including body and comments.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "number" => %{"type" => "integer", "description" => "Issue or PR number"},
          "repo" => %{
            "type" => "string",
            "description" => "Repository in 'owner/repo' format (optional if default_repo is configured)"
          }
        },
        "required" => ["number"]
      },
      callback: &call/1
    )
  end

  def call(%{"number" => number} = params) do
    repo = Map.get(params, "repo") || ExCalibur.Settings.get(:default_repo)

    case repo do
      nil ->
        {:error, "repo required — pass 'repo' param or configure default_repo in settings"}

      repo ->
        args = ["issue", "view", to_string(number), "--repo", repo, "--json", "number,title,body,state,comments"]

        case System.cmd("gh", args, stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {error, _} -> {:error, error}
        end
    end
  end
end
