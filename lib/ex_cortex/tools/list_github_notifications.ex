defmodule ExCortex.Tools.ListGithubNotifications do
  @moduledoc "Tool: list GitHub notifications via gh API."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "list_github_notifications",
      description: "List your GitHub notifications (unread by default).",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "all" => %{"type" => "boolean", "description" => "Include read notifications (default false)"}
        },
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(params) do
    include_all = Map.get(params, "all", false)
    endpoint = if include_all, do: "notifications?all=true", else: "notifications"

    case System.cmd("gh", ["api", endpoint], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end
end
