defmodule ExCalibur.Tools.QueryLoreTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Lore
  alias ExCalibur.Tools.QueryLore

  test "req_llm_tool returns a valid ReqLLM.Tool struct" do
    tool = QueryLore.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "query_lore"

    assert tool.description ==
             "Search the lore store for entries matching the given tags. Returns recent matching entries."

    assert Map.has_key?(tool.parameter_schema, "properties")
    assert Map.has_key?(tool.parameter_schema["properties"], "tags")
    assert Map.has_key?(tool.parameter_schema["properties"], "limit")
  end

  test "call/1 returns summaries of matching lore entries" do
    {:ok, _} = Lore.create_entry(%{title: "Alpha", body: "First entry body", tags: ["alpha"]})
    {:ok, _} = Lore.create_entry(%{title: "Beta", body: "Second entry body", tags: ["beta"]})

    {:ok, result} = QueryLore.call(%{"tags" => ["alpha"]})
    assert String.contains?(result, "Alpha")
    assert String.contains?(result, "First entry body")
    refute String.contains?(result, "Beta")
  end

  test "call/1 with empty tags returns all entries up to limit" do
    for i <- 1..3 do
      {:ok, _} = Lore.create_entry(%{title: "Entry #{i}", body: "Body #{i}", tags: []})
    end

    {:ok, result} = QueryLore.call(%{"tags" => []})
    assert result != ""
  end

  test "call/1 with no input defaults to empty tags" do
    {:ok, _} = Lore.create_entry(%{title: "Solo", body: "solo body", tags: []})
    {:ok, result} = QueryLore.call(%{})
    assert is_binary(result)
  end

  test "call/1 respects limit parameter" do
    for i <- 1..6 do
      {:ok, _} =
        Lore.create_entry(%{title: "Item #{i}", body: "body #{i}", tags: ["shared"]})
    end

    {:ok, result} = QueryLore.call(%{"tags" => ["shared"], "limit" => 3})
    count = result |> String.split("---") |> length()
    assert count <= 3
  end
end
