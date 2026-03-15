defmodule ExCortex.Tools.JqQuery do
  @moduledoc "Tool: run a jq expression against a JSON string."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "jq_query",
      description: "Run a jq expression against a JSON string and return the result.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "expression" => %{"type" => "string", "description" => "jq expression (e.g. '.[] | .name')"},
          "json" => %{"type" => "string", "description" => "JSON string to query"}
        },
        "required" => ["expression", "json"]
      },
      callback: &call/1
    )
  end

  def call(%{"expression" => expr, "json" => json}) do
    case System.cmd("jq", [expr], input: json, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end
end
