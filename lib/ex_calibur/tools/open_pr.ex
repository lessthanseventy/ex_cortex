defmodule ExCalibur.Tools.OpenPR do
  @moduledoc "Tool: open a GitHub pull request via gh CLI."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "open_pr",
      description: "Open a GitHub pull request from the current branch.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "title" => %{"type" => "string", "description" => "PR title"},
          "body" => %{"type" => "string", "description" => "PR description (markdown)"},
          "base" => %{"type" => "string", "description" => "Base branch (default: main)"}
        },
        "required" => ["title", "body"]
      },
      callback: &call/1
    )
  end

  def call(%{"title" => title, "body" => body} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())
    base = Map.get(params, "base", "main")
    args = ["pr", "create", "--title", title, "--body", body, "--base", base]

    case System.cmd("gh", args, cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "PR created: #{String.trim(output)}"}
      {output, _} -> {:error, "PR creation failed: #{output}"}
    end
  end
end
