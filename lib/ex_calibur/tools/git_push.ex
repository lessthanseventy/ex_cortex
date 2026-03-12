defmodule ExCalibur.Tools.GitPush do
  @moduledoc "Tool: push a branch to origin."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "git_push",
      description: "Push the current branch to origin.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "branch" => %{"type" => "string", "description" => "Branch name to push"}
        },
        "required" => ["branch"]
      },
      callback: &call/1
    )
  end

  def call(%{"branch" => branch} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())

    case System.cmd("git", ["push", "-u", "origin", branch], cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "Pushed #{branch}: #{String.trim(output)}"}
      {output, _} -> {:error, "Push failed: #{output}"}
    end
  end
end
