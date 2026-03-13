defmodule ExCalibur.Tools.GitCommit do
  @moduledoc "Tool: stage files and create a git commit in the working directory."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "git_commit",
      description:
        "Stage specific files and create a git commit. REQUIRED: pass working_dir as the worktree path returned by setup_worktree so commits go to the branch, not main.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "files" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Files to stage (relative paths)"
          },
          "message" => %{"type" => "string", "description" => "Commit message"},
          "working_dir" => %{
            "type" => "string",
            "description" => "Absolute path to the worktree directory (from setup_worktree)"
          }
        },
        "required" => ["files", "message", "working_dir"]
      },
      callback: &call/1
    )
  end

  def call(%{"files" => files, "message" => message} = params) do
    working_dir = Map.get(params, "working_dir") || File.cwd!()

    Enum.each(files, fn file ->
      System.cmd("git", ["add", file], cd: working_dir, stderr_to_stdout: true)
    end)

    # Styler guard: auto-format staged Elixir files before committing
    elixir_files =
      Enum.filter(files, &(String.ends_with?(&1, ".ex") or String.ends_with?(&1, ".exs")))

    if elixir_files != [] do
      System.cmd("mix", ["format" | elixir_files], cd: working_dir, stderr_to_stdout: true)

      # Re-stage formatted files
      Enum.each(elixir_files, fn file ->
        System.cmd("git", ["add", file], cd: working_dir, stderr_to_stdout: true)
      end)
    end

    # Append co-author trailer so the AI agent is credited in the commit log
    full_message = message <> "\n\nCo-Authored-By: ExCalibur Dev Team <devteam@excalibur.local>"

    args = [
      "commit",
      "--author=ExCalibur Dev Team <devteam@excalibur.local>",
      "-m",
      full_message
    ]

    case System.cmd("git", args, cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "Committed: #{String.trim(output)}"}
      {output, _} -> {:error, "Commit failed: #{output}"}
    end
  end
end
