defmodule ExCortex.Tools.RestartApp do
  @moduledoc "Tool: graceful restart of the ExCortex application."

  require Logger

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "restart_app",
      description: "Gracefully restart the ExCortex application after pulling new code.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "mode" => %{"type" => "string", "description" => "dev (default) or docker"}
        },
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(params) do
    mode = Map.get(params, "mode", "dev")
    project_dir = File.cwd!()

    script =
      case mode do
        "docker" -> Path.join(project_dir, "bin/restart-docker.sh")
        _ -> Path.join(project_dir, "bin/restart.sh")
      end

    Logger.info("[RestartApp] Triggering restart via #{script}")
    Port.open({:spawn_executable, script}, [:binary, args: [project_dir]])
    {:ok, "Restart initiated via #{script} — app will restart momentarily"}
  end
end
