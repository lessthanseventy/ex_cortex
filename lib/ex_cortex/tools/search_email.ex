defmodule ExCortex.Tools.SearchEmail do
  @moduledoc "Tool: search email index via notmuch."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "search_email",
      description: """
      Search the local email index via notmuch. Covers ALL mail folders — inbox, sent, archive, drafts, etc.

      Output modes:
      - "results" (default): matching thread summaries
      - "count": total number of matching messages (use for "how many" questions)
      - "summary": structured JSON with subjects, dates, senders
      - "tags": list all available tags (ignores query). Call this first to discover tag names.
      - "folders": list all available mail folders (ignores query). Call this first to discover folder paths.

      IMPORTANT: Folder paths include the account prefix (e.g. folder:account/Sent NOT folder:Sent).
      Always use "folders" output first to discover the correct paths before querying by folder.

      Query syntax:
      - tag:inbox — messages tagged inbox
      - tag:sent OR folder:account/Sent — sent messages (check tags/folders first)
      - from:user@example.com — by sender (use this to find sent mail if you know the user's address)
      - to:recipient@example.com — by recipient
      - subject:invoice — subject keyword
      - date:1M.. — last month to now
      - date:2024-01-01..2024-12-31 — date range
      - AND, OR, NOT, parentheses — combinators
      - * — all messages
      """,
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{
            "type" => "string",
            "description" => "Notmuch search query. Required for results/count/summary. Ignored for tags/folders."
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum results for results/summary modes (default 20, ignored for count/tags/folders)"
          },
          "output" => %{
            "type" => "string",
            "enum" => ["results", "count", "summary", "tags", "folders"],
            "description" =>
              "Output mode: results (default), count (total matches), summary (JSON), tags (list all tags), folders (list all folders)"
          }
        },
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(params) do
    mode = Map.get(params, "output", "results")
    query = Map.get(params, "query", "*")
    limit = Map.get(params, "limit", 20)
    args = build_args(query, limit, mode)

    case System.cmd("notmuch", args, stderr_to_stdout: true) do
      {result, 0} -> format_output(result, mode)
      {error, _} -> {:error, error}
    end
  end

  defp build_args(_query, _limit, "tags") do
    config_args() ++ ["search", "--output=tags", "*"]
  end

  defp build_args(_query, _limit, "folders") do
    config_args() ++ ["search", "--output=files", "*"]
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

  defp format_output(result, "folders") do
    # Extract unique folder paths from file paths (strip /cur/ /new/ /tmp/ and filenames)
    folders =
      result
      |> String.split("\n", trim: true)
      |> Enum.map(fn path ->
        path
        |> String.split("/")
        |> Enum.reverse()
        |> Enum.drop(2)
        |> Enum.reverse()
        |> Enum.drop_while(&(&1 != "mail"))
        |> Enum.drop(1)
        |> Enum.join("/")
      end)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.reject(&(&1 == ""))

    {:ok, "Available folders (use as folder:<path>):\n" <> Enum.join(folders, "\n")}
  end

  defp format_output(result, _), do: {:ok, result}

  defp config_args do
    case ExCortex.Settings.get(:notmuch_db_path) do
      nil -> []
      db_path -> ["--config=#{db_path}"]
    end
  end
end
