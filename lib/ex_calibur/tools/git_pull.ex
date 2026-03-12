defmodule ExCalibur.Tools.GitPull do
  @moduledoc "Tool: pull latest changes from origin."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "git_pull",
      description: "Pull latest changes from origin into the live copy. Fast-forward only.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{},
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())

    case System.cmd("git", ["pull", "--ff-only"], cd: working_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, "Pulled: #{String.trim(output)}"}
      {output, _} -> {:error, "Pull failed: #{output}"}
    end
  end
end
