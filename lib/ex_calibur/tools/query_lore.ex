defmodule ExCalibur.Tools.QueryLore do
  @moduledoc "Tool: search lore entries by tags."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "query_lore",
      description:
        "Search the lore store for entries matching the given tags. Returns recent matching entries.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "tags" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Tags to filter by"
          },
          "limit" => %{"type" => "integer", "description" => "Max entries to return (default 5)"}
        },
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(%{"tags" => tags} = input) do
    limit = Map.get(input, "limit", 5)
    entries = ExCalibur.Lore.list_entries(tags: tags) |> Enum.take(limit)
    summaries = Enum.map(entries, fn e -> "#{e.title}: #{String.slice(e.body || "", 0, 200)}" end)
    {:ok, Enum.join(summaries, "\n---\n")}
  end

  def call(input), do: call(Map.put_new(input, "tags", []))
end
