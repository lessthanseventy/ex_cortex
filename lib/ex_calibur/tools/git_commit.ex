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

    case System.cmd("git", ["commit", "-m", message], cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "Committed: #{String.trim(output)}"}
      {output, _} -> {:error, "Commit failed: #{output}"}
    end
  end
end
