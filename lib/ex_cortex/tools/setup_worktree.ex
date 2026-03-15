defmodule ExCortex.Tools.SetupWorktree do
  @moduledoc "Tool: create an isolated git worktree for implementing a GitHub issue."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "setup_worktree",
      description: """
      Create an isolated git worktree for implementing a GitHub issue.
      Returns the worktree path — pass this as `working_dir` to all subsequent
      write_file, edit_file, git_commit, git_push, and open_pr calls.
      """,
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "issue_id" => %{
            "type" => "string",
            "description" => "GitHub issue number or short slug (e.g. '42' or 'fix-auth')"
          }
        },
        "required" => ["issue_id"]
      },
      callback: &call/1
    )
  end

  def call(%{"issue_id" => issue_id}) do
    repo_path = File.cwd!()

    case ExCortex.Worktree.create(repo_path, issue_id) do
      {:ok, path} ->
        {:ok, "Worktree ready at #{path} — use this as working_dir for all file and git operations."}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
