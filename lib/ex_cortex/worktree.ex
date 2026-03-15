defmodule ExCortex.Worktree do
  @moduledoc "Manages git worktrees for isolated code changes."

  require Logger

  @worktree_dir ".worktrees"

  @doc "Create a worktree for a given issue ID. Returns {:ok, path} or {:error, reason}."
  def create(repo_path, issue_id) do
    worktree_path = Path.join([repo_path, @worktree_dir, to_string(issue_id)])
    branch = "self-improve/#{issue_id}"

    File.mkdir_p!(Path.join(repo_path, @worktree_dir))

    case System.cmd("git", ["worktree", "add", worktree_path, "-b", branch],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Logger.info("[Worktree] Created #{worktree_path} on branch #{branch}")
        {:ok, worktree_path}

      {output, _} ->
        {:error, "Failed to create worktree: #{output}"}
    end
  end

  @doc "Remove a worktree and its branch."
  def remove(repo_path, issue_id) do
    worktree_path = Path.join([repo_path, @worktree_dir, to_string(issue_id)])
    branch = "self-improve/#{issue_id}"

    System.cmd("git", ["worktree", "remove", worktree_path, "--force"],
      cd: repo_path,
      stderr_to_stdout: true
    )

    System.cmd("git", ["branch", "-D", branch], cd: repo_path, stderr_to_stdout: true)
    Logger.info("[Worktree] Removed #{worktree_path}")
    :ok
  end

  @doc "Return the path for a worktree without creating it."
  def path(repo_path, issue_id) do
    Path.join([repo_path, @worktree_dir, to_string(issue_id)])
  end
end
