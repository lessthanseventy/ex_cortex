defmodule ExCortex.Tools.SearchEmail do
  @moduledoc "Tool: search email index via notmuch."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "search_email",
      description: """
      Search emails using notmuch query syntax. Returns matching threads, counts, or structured summaries.

      Query syntax examples:
      - tag:inbox — messages tagged inbox
      - tag:unread — unread messages
      - from:alice@example.com — messages from a sender
      - to:bob@example.com — messages to a recipient
      - subject:invoice — subject line contains "invoice"
      - date:1M.. — messages from the last month
      - date:2025-01-01..2025-03-01 — messages in a date range
      - from:alice AND subject:report — combine with AND
      - from:alice OR from:bob — combine with OR
      - NOT tag:spam — negation
      - folder:INBOX — messages in a specific folder
      - * — match all messages
      - from:alice AND date:1w.. AND tag:unread — complex queries

      Combinators: AND, OR, NOT, parentheses for grouping.
      """,
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{
            "type" => "string",
            "description" => "Notmuch search query"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum number of results to return (default 20)"
          },
          "output" => %{
            "type" => "string",
            "enum" => ["results", "count", "summary"],
            "description" =>
              "Output mode: results (default) returns text search results, count returns total matching messages, summary returns structured JSON"
          }
        },
        "required" => ["query"]
      },
      callback: &call/1
    )
  end

  def call(%{"query" => query} = params) do
    limit = Map.get(params, "limit", 20)
    mode = Map.get(params, "output", "results")
    args = build_args(query, limit, mode)

    case System.cmd("notmuch", args, stderr_to_stdout: true) do
      {result, 0} -> {:ok, result}
      {error, _} -> {:error, error}
    end
  end

  defp build_args(query, _limit, "count") do
    config_args() ++ ["count", query]
  end

  defp build_args(query, limit, "summary") do
    config_args() ++ ["search", "--limit=#{limit}", "--format=json", "--output=summary", query]
  end

  defp build_args(query, limit, _results) do
    config_args() ++ ["search", "--limit=#{limit}", "--format=text", query]
  end

  defp config_args do
    case ExCortex.Settings.get(:notmuch_db_path) do
      nil -> []
      db_path -> ["--config=#{db_path}"]
    end
  end
end
