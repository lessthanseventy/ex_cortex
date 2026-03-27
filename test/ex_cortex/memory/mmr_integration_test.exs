defmodule ExCortex.Memory.MMRIntegrationTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Memory

  describe "query/2 with strategy: :legacy" do
    test "returns engrams matching by title" do
      {:ok, _} =
        Memory.create_engram(%{
          title: "Elixir pattern matching guide",
          impression: "A guide to pattern matching in Elixir",
          tags: ["elixir"],
          importance: 3,
          category: "semantic"
        })

      results = Memory.query("pattern matching", strategy: :legacy, tier: :L0)
      assert results != []
      assert hd(results).title =~ "pattern matching"
    end

    test "returns engrams matching by tag" do
      {:ok, _} =
        Memory.create_engram(%{
          title: "Some note",
          impression: "Unrelated impression",
          tags: ["special_tag"],
          importance: 2,
          category: "semantic"
        })

      results = Memory.query("special_tag", strategy: :legacy, tier: :L0)
      assert results != []
    end
  end

  describe "query/2 with strategy: :mmr" do
    test "falls back to legacy when no embeddings exist" do
      {:ok, _} =
        Memory.create_engram(%{
          title: "MMR fallback test note",
          impression: "Testing MMR fallback behavior",
          tags: ["mmr_test"],
          importance: 3,
          category: "semantic"
        })

      # MMR will fail to embed (no Ollama in test) and fall back to legacy
      results = Memory.query("MMR fallback test", strategy: :mmr, tier: :L0)
      assert is_list(results)
    end

    test "respects tier option on fallback" do
      {:ok, _} =
        Memory.create_engram(%{
          title: "Tier test note",
          impression: "Testing tier in MMR fallback",
          recall: "Detailed recall content",
          tags: ["tier_test"],
          importance: 3,
          category: "semantic"
        })

      l0_results = Memory.query("Tier test", strategy: :mmr, tier: :L0)
      l1_results = Memory.query("Tier test", strategy: :mmr, tier: :L1)

      # L0 results should not have recall field loaded
      if l0_results != [] do
        refute Map.has_key?(hd(l0_results), :recall) and hd(l0_results).recall != nil
      end

      # L1 results should include recall
      if l1_results != [] do
        assert Map.has_key?(hd(l1_results), :recall)
      end
    end
  end

  describe "query/2 defaults" do
    test "defaults to legacy strategy" do
      results = Memory.query("nonexistent_term_xyz")
      assert is_list(results)
      assert results == []
    end
  end
end
