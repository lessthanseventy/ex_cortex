defmodule ExCortex.Tools.QueryDictionaryTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Library
  alias ExCortex.Tools.QueryDictionary

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, _} =
      Library.create_dictionary(%{
        name: "test_teams_#{suffix}",
        content:
          "team,abbreviation,league\nKansas City Chiefs,KC,NFL\nGreen Bay Packers,GB,NFL\nLos Angeles Lakers,LAL,NBA",
        content_type: "csv"
      })

    {:ok, _} =
      Library.create_dictionary(%{
        name: "test_glossary_#{suffix}",
        content: "Engram: a stored memory\nThought: a pipeline run\nNeuron: an agent role",
        content_type: "text"
      })

    %{suffix: suffix}
  end

  test "returns matching CSV rows with header", %{suffix: s} do
    {:ok, result} = QueryDictionary.call(%{"dictionary" => "test_teams_#{s}", "query" => "kansas"})
    assert result =~ "Kansas City Chiefs"
    assert result =~ "team,abbreviation,league"
    refute result =~ "Green Bay Packers"
  end

  test "is case-insensitive", %{suffix: s} do
    {:ok, result} = QueryDictionary.call(%{"dictionary" => "test_teams_#{s}", "query" => "KANSAS"})
    assert result =~ "Kansas City Chiefs"
  end

  test "returns matching text lines", %{suffix: s} do
    {:ok, result} = QueryDictionary.call(%{"dictionary" => "test_glossary_#{s}", "query" => "thought"})
    assert result =~ "Thought: a pipeline run"
    refute result =~ "Engram:"
  end

  test "returns error when dictionary not found" do
    {:error, msg} = QueryDictionary.call(%{"dictionary" => "nonexistent", "query" => "foo"})
    assert msg =~ "not found"
  end

  test "returns no-match message when query has no hits", %{suffix: s} do
    {:ok, result} =
      QueryDictionary.call(%{"dictionary" => "test_teams_#{s}", "query" => "zzz_no_match"})

    assert result =~ "No matches"
  end

  test "req_llm_tool/0 returns a valid ReqLLM.Tool struct" do
    tool = QueryDictionary.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "query_dictionary"
  end
end
