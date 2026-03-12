defmodule ExCalibur.Tools.QueryDictionaryTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Library
  alias ExCalibur.Tools.QueryDictionary

  setup do
    {:ok, _} =
      Library.create_dictionary(%{
        name: "sports_teams",
        content:
          "team,abbreviation,league\nKansas City Chiefs,KC,NFL\nGreen Bay Packers,GB,NFL\nLos Angeles Lakers,LAL,NBA",
        content_type: "csv"
      })

    {:ok, _} =
      Library.create_dictionary(%{
        name: "glossary",
        content: "Lore: accumulated knowledge\nQuest: a pipeline run\nMember: a role in a guild",
        content_type: "text"
      })

    :ok
  end

  test "returns matching CSV rows with header" do
    {:ok, result} = QueryDictionary.call(%{"dictionary" => "sports_teams", "query" => "kansas"})
    assert result =~ "Kansas City Chiefs"
    assert result =~ "team,abbreviation,league"
    refute result =~ "Green Bay Packers"
  end

  test "is case-insensitive" do
    {:ok, result} = QueryDictionary.call(%{"dictionary" => "sports_teams", "query" => "KANSAS"})
    assert result =~ "Kansas City Chiefs"
  end

  test "returns matching text lines" do
    {:ok, result} = QueryDictionary.call(%{"dictionary" => "glossary", "query" => "quest"})
    assert result =~ "Quest: a pipeline run"
    refute result =~ "Lore:"
  end

  test "returns error when dictionary not found" do
    {:error, msg} = QueryDictionary.call(%{"dictionary" => "nonexistent", "query" => "foo"})
    assert msg =~ "not found"
  end

  test "returns no-match message when query has no hits" do
    {:ok, result} =
      QueryDictionary.call(%{"dictionary" => "sports_teams", "query" => "zzz_no_match"})

    assert result =~ "No matches"
  end

  test "req_llm_tool/0 returns a valid ReqLLM.Tool struct" do
    tool = QueryDictionary.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "query_dictionary"
  end
end
