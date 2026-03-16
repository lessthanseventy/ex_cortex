defmodule ExCortex.Tools.QueryMemory do
  @moduledoc "Tool: search engrams (memories) by text, tags, category, and date."

  alias ExCortex.Memory

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "query_memory",
      description: """
      Search the engram memory store. Engrams are memories/artifacts stored with tiered detail \
      (impression, recall, body). Each has a category (semantic = facts/concepts, \
      episodic = events/experiences, procedural = how-to/processes), importance 1-5, and tags.

      Examples:
      - Find recent code-related memories: {"tags": ["code"], "limit": 10}
      - Count procedural memories: {"category": "procedural", "output": "count"}
      - Free-text search: {"search": "deployment", "limit": 5}
      - Memories since a date: {"since": "2026-01-01", "category": "episodic"}
      """,
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "tags" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Tags to filter by (matched with array overlap)"
          },
          "search" => %{
            "type" => "string",
            "description" => "Free-text search across titles and impressions"
          },
          "category" => %{
            "type" => "string",
            "enum" => ["semantic", "episodic", "procedural"],
            "description" => "Filter by engram category"
          },
          "since" => %{
            "type" => "string",
            "description" => "ISO date (e.g. 2026-01-15). Only return engrams created on or after this date"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Max entries to return (default 10)"
          },
          "output" => %{
            "type" => "string",
            "enum" => ["results", "count"],
            "description" => "Output mode: 'results' returns entries (default), 'count' returns a count"
          }
        },
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(input) do
    tags = Map.get(input, "tags", [])
    search = Map.get(input, "search")
    category = Map.get(input, "category")
    since = parse_since(Map.get(input, "since"))
    limit = Map.get(input, "limit", 10)
    output = Map.get(input, "output", "results")

    case output do
      "count" ->
        count = Memory.count_engrams(tags: tags, category: category, since: since)
        {:ok, "Count: #{count}"}

      _ ->
        entries = fetch_entries(search, tags, limit)
        filtered = apply_filters(entries, category, since)
        format_results(filtered)
    end
  end

  defp fetch_entries(nil, tags, limit) do
    [tags: tags]
    |> Memory.list_engrams()
    |> Enum.take(limit)
  end

  defp fetch_entries(search, _tags, limit) do
    Memory.query(search, tier: :L0, limit: limit)
  end

  defp apply_filters(entries, category, since) do
    entries
    |> maybe_filter_category(category)
    |> maybe_filter_since(since)
  end

  defp maybe_filter_category(entries, nil), do: entries

  defp maybe_filter_category(entries, category) do
    Enum.filter(entries, &(&1.category == category))
  end

  defp maybe_filter_since(entries, nil), do: entries

  defp maybe_filter_since(entries, %NaiveDateTime{} = since) do
    Enum.filter(entries, &(NaiveDateTime.compare(&1.inserted_at, since) != :lt))
  end

  defp parse_since(nil), do: nil

  defp parse_since(date_str) when is_binary(date_str) do
    case NaiveDateTime.from_iso8601(date_str <> "T00:00:00") do
      {:ok, ndt} -> ndt
      _ -> nil
    end
  end

  defp format_results([]), do: {:ok, "No engrams found."}

  defp format_results(entries) do
    summaries =
      Enum.map(entries, fn e ->
        cat = e.category || "uncategorized"
        text = String.slice(e.impression || e.body || "", 0, 200)
        "#{e.title} [#{cat}]: #{text}"
      end)

    {:ok, Enum.join(summaries, "\n---\n")}
  end
end
