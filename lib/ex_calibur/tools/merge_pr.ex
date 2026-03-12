defmodule ExCalibur.Tools.MergePR do
  @moduledoc "Tool: merge a GitHub pull request via gh CLI."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "merge_pr",
      description: "Merge a GitHub pull request by number.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "pr_number" => %{"type" => "integer", "description" => "PR number to merge"},
          "method" => %{
            "type" => "string",
            "description" => "merge, squash, or rebase (default: squash)"
          }
        },
        "required" => ["pr_number"]
      },
      callback: &call/1
    )
  end

  def call(%{"pr_number" => pr_number} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())
    method = Map.get(params, "method", "squash")
    args = ["pr", "merge", to_string(pr_number), "--#{method}", "--delete-branch"]

    case System.cmd("gh", args, cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "PR ##{pr_number} merged: #{String.trim(output)}"}
      {output, _} -> {:error, "Merge failed: #{output}"}
    end
  end
end
