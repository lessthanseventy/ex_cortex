defmodule ExCortex.Tools.WebSearch do
  @moduledoc "Tool: search the web via DuckDuckGo using ddgr."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "web_search",
      description:
        "Search the web via DuckDuckGo. Returns results with title, URL, and snippet. Example: web_search(query: \"elixir phoenix deployment\", num: 5)",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "Search query"},
          "num" => %{"type" => "integer", "description" => "Number of results to return (default 10)"}
        },
        "required" => ["query"]
      },
      callback: &call/1
    )
  end

  def call(%{"query" => query} = params) do
    num = Map.get(params, "num", 10)

    case System.cmd("ddgr", ["--json", "--num", to_string(num), "--noua", query], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end
end
