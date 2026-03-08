defmodule ExCellenceServer.Sources.GitWatcher do
  @moduledoc false
  @behaviour ExCellenceServer.Sources.Behaviour

  alias ExCellenceServer.Sources.SourceItem

  @impl true
  def init(config) do
    repo_path = config["repo_path"] || ""
    branch = config["branch"] || "main"

    if repo_path == "" do
      {:error, "repo_path is required"}
    else
      last_sha = config["last_sha"] || get_current_sha(repo_path, branch)
      {:ok, %{last_sha: last_sha}}
    end
  end

  @impl true
  def fetch(state, config) do
    repo_path = config["repo_path"]
    branch = config["branch"] || "main"

    last_sha = state.last_sha

    case get_current_sha(repo_path, branch) do
      nil ->
        {:error, "could not read HEAD for #{branch}"}

      ^last_sha ->
        {:ok, [], state}

      current_sha ->
        items = build_items(repo_path, state.last_sha, current_sha, config)
        {:ok, items, %{state | last_sha: current_sha}}
    end
  end

  defp get_current_sha(repo_path, branch) do
    case System.cmd("git", ["rev-parse", branch], cd: repo_path, stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> nil
    end
  end

  defp build_items(repo_path, last_sha, current_sha, config) do
    {log_output, 0} =
      System.cmd("git", ["log", "--oneline", "#{last_sha}..#{current_sha}"],
        cd: repo_path,
        stderr_to_stdout: true
      )

    {diff_output, 0} =
      System.cmd("git", ["diff", "#{last_sha}..#{current_sha}"],
        cd: repo_path,
        stderr_to_stdout: true
      )

    commits =
      log_output
      |> String.split("\n", trim: true)
      |> Enum.map(fn line ->
        [sha | message_parts] = String.split(line, " ", parts: 2)
        {sha, Enum.join(message_parts, " ")}
      end)

    Enum.map(commits, fn {sha, message} ->
      %SourceItem{
        source_id: config["source_id"],
        guild_name: config["guild_name"],
        type: "commit",
        content: "Commit: #{sha} #{message}\n\n#{diff_output}",
        metadata: %{sha: sha, message: message, branch: config["branch"] || "main"}
      }
    end)
  end
end
