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
    repo_path = File.cwd!()
    method = Map.get(params, "method", "squash")
    args = ["pr", "merge", to_string(pr_number), "--#{method}", "--delete-branch"]

    case System.cmd("gh", args, cd: repo_path, stderr_to_stdout: true) do
      {output, 0} ->
        cleanup_si_worktrees(repo_path)
        {:ok, "PR ##{pr_number} merged: #{String.trim(output)}"}

      {output, _} ->
        {:error, "Merge failed: #{output}"}
    end
  end

  defp cleanup_si_worktrees(repo_path) do
    worktrees_dir = Path.join(repo_path, ".worktrees")

    case File.ls(worktrees_dir) do
      {:ok, entries} ->
        Enum.each(entries, fn entry ->
          path = Path.join(worktrees_dir, entry)
          ExCalibur.Worktree.remove(repo_path, entry)
          File.rm_rf(path)
        end)

        System.cmd("git", ["worktree", "prune"], cd: repo_path, stderr_to_stdout: true)

      _ ->
        :ok
    end
  end
end
