defmodule ExCortex.Tools.OpenPR do
  @moduledoc "Tool: open a GitHub pull request via gh CLI."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "open_pr",
      description:
        "Open a real GitHub pull request from the current branch. Creates a PR on github.com with a title, full description, and closes the issue. REQUIRED: pass working_dir as the worktree path returned by setup_worktree.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "title" => %{
            "type" => "string",
            "description" => "PR title (e.g. 'fix: improve error handling in evaluator (closes #42)')"
          },
          "body" => %{
            "type" => "string",
            "description" =>
              "Full PR description in markdown — include: what changed and why, which files, how to test, and 'Closes #N' to auto-close the issue"
          },
          "base" => %{"type" => "string", "description" => "Base branch (default: main)"},
          "working_dir" => %{
            "type" => "string",
            "description" => "Absolute path to the worktree directory (from setup_worktree)"
          }
        },
        "required" => ["title", "body", "working_dir"]
      },
      callback: &call/1
    )
  end

  def call(%{"title" => title, "body" => body} = params) do
    working_dir = Map.get(params, "working_dir") || File.cwd!()
    base = Map.get(params, "base", "main")
    args = ["pr", "create", "--title", title, "--body", body, "--base", base]

    case System.cmd("gh", args, cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "PR created: #{String.trim(output)}"}
      {output, _} -> {:error, "PR creation failed: #{output}"}
    end
  end
end
