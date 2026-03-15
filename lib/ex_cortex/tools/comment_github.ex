defmodule ExCortex.Tools.CommentGithub do
  @moduledoc "Tool: add a comment to a GitHub issue or PR via gh CLI."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "comment_github",
      description: "Add a comment to a GitHub issue or pull request.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "number" => %{"type" => "integer", "description" => "Issue or PR number"},
          "body" => %{"type" => "string", "description" => "Comment body (markdown supported)"},
          "repo" => %{
            "type" => "string",
            "description" => "Repository in 'owner/repo' format (optional if default_repo configured)"
          }
        },
        "required" => ["number", "body"]
      },
      callback: &call/1
    )
  end

  def call(%{"number" => number, "body" => body} = params) do
    repo = Map.get(params, "repo") || ExCortex.Settings.get(:default_repo)

    case repo do
      nil ->
        {:error, "repo required — pass 'repo' param or configure default_repo in settings"}

      repo ->
        args = ["issue", "comment", to_string(number), "--body", body, "--repo", repo]

        case System.cmd("gh", args, stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {error, _} -> {:error, error}
        end
    end
  end
end
