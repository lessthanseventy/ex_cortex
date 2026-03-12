defmodule ExCalibur.Tools.GitCommit do
  @moduledoc "Tool: stage files and create a git commit in the working directory."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "git_commit",
      description: "Stage specific files and create a git commit.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "files" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Files to stage (relative paths)"
          },
          "message" => %{"type" => "string", "description" => "Commit message"}
        },
        "required" => ["files", "message"]
      },
      callback: &call/1
    )
  end

  def call(%{"files" => files, "message" => message} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())

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

    case System.cmd("git", ["commit", "-m", message], cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "Committed: #{String.trim(output)}"}
      {output, _} -> {:error, "Commit failed: #{output}"}
    end
  end
end
