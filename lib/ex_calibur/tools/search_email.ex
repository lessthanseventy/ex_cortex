defmodule ExCalibur.Tools.SearchEmail do
  @moduledoc "Tool: search email index via notmuch."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "search_email",
      description: "Search emails using notmuch query syntax. Returns matching message IDs and summaries.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "Notmuch search query (e.g. 'from:alice subject:invoice date:1M..')"},
          "limit" => %{"type" => "integer", "description" => "Maximum number of results to return (default 20)"}
        },
        "required" => ["query"]
      },
      callback: &call/1
    )
  end

  def call(%{"query" => query} = params) do
    limit = Map.get(params, "limit", 20)
    db_path = ExCalibur.Settings.get(:notmuch_db_path)
    args = build_args(db_path, query, limit)

    case System.cmd("notmuch", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  defp build_args(nil, query, limit) do
    ["search", "--limit=#{limit}", "--format=text", query]
  end

  defp build_args(db_path, query, limit) do
    ["--config=#{db_path}", "search", "--limit=#{limit}", "--format=text", query]
  end
end
