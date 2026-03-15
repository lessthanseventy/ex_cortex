defmodule ExCortex.Tools.QueryAxiomTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Lexicon
  alias ExCortex.Tools.QueryAxiom

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, _} =
      Lexicon.create_axiom(%{
        name: "test_teams_#{suffix}",
        content:
          "team,abbreviation,league\nKansas City Chiefs,KC,NFL\nGreen Bay Packers,GB,NFL\nLos Angeles Lakers,LAL,NBA",
        content_type: "csv"
      })

    {:ok, _} =
      Lexicon.create_axiom(%{
        name: "test_glossary_#{suffix}",
        content: "Engram: a stored memory\nRumination: a pipeline run\nNeuron: an agent role",
        content_type: "text"
      })

    %{suffix: suffix}
  end

  test "returns matching CSV rows with header", %{suffix: s} do
    {:ok, result} = QueryAxiom.call(%{"axiom" => "test_teams_#{s}", "query" => "kansas"})
    assert result =~ "Kansas City Chiefs"
    assert result =~ "team,abbreviation,league"
    refute result =~ "Green Bay Packers"
  end

  test "is case-insensitive", %{suffix: s} do
    {:ok, result} = QueryAxiom.call(%{"axiom" => "test_teams_#{s}", "query" => "KANSAS"})
    assert result =~ "Kansas City Chiefs"
  end

  test "returns matching text lines", %{suffix: s} do
    {:ok, result} = QueryAxiom.call(%{"axiom" => "test_glossary_#{s}", "query" => "rumination"})
    assert result =~ "Rumination: a pipeline run"
    refute result =~ "Engram:"
  end

  test "returns error when axiom not found" do
    {:error, msg} = QueryAxiom.call(%{"axiom" => "nonexistent", "query" => "foo"})
    assert msg =~ "not found"
  end

  test "returns no-match message when query has no hits", %{suffix: s} do
    {:ok, result} =
      QueryAxiom.call(%{"axiom" => "test_teams_#{s}", "query" => "zzz_no_match"})

    assert result =~ "No matches"
  end

  test "req_llm_tool/0 returns a valid ReqLLM.Tool struct" do
    tool = QueryAxiom.req_llm_tool()
    assert is_struct(tool, ReqLLM.Tool)
    assert tool.name == "query_axiom"
  end
end
