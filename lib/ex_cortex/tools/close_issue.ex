defmodule ExCortex.Tools.CloseIssue do
  @moduledoc "Tool: close a GitHub issue with a comment."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "close_issue",
      description: "Close a GitHub issue with an optional comment.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "issue_number" => %{"type" => "integer", "description" => "Issue number to close"},
          "comment" => %{
            "type" => "string",
            "description" => "Comment to add before closing (optional)"
          },
          "repo" => %{
            "type" => "string",
            "description" => "Repository in owner/repo format (optional)"
          }
        },
        "required" => ["issue_number"]
      },
      callback: &call/1
    )
  end

  def call(%{"issue_number" => issue_number} = params) do
    repo = Map.get(params, "repo") || ExCortex.Settings.get(:default_repo)

    if is_nil(repo) do
      {:error, "repo required — pass 'repo' param or configure default_repo"}
    else
      comment = Map.get(params, "comment")

      if comment do
        System.cmd(
          "gh",
          ["issue", "comment", to_string(issue_number), "--body", comment, "--repo", repo],
          stderr_to_stdout: true
        )
      end

      case System.cmd("gh", ["issue", "close", to_string(issue_number), "--repo", repo], stderr_to_stdout: true) do
        {output, 0} -> {:ok, "Issue ##{issue_number} closed: #{String.trim(output)}"}
        {output, _} -> {:error, "Close failed: #{output}"}
      end
    end
  end
end
