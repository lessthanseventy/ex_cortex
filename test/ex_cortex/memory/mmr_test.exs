defmodule ExCortex.Memory.MMRTest do
  use ExUnit.Case, async: true

  alias ExCortex.Memory.MMR

  describe "rerank/4" do
    test "returns diverse results from candidates" do
      query = [1.0, 0.0, 0.0]

      # id 1 and 2 are near-duplicates (both point mostly along x-axis)
      # id 3 is orthogonal (points along y-axis) — diverse pick after id 1
      candidates = [
        %{id: 1, embedding: [1.0, 0.0, 0.0]},
        %{id: 2, embedding: [0.99, 0.01, 0.0]},
        %{id: 3, embedding: [0.0, 1.0, 0.0]}
      ]

      result = MMR.rerank(query, candidates, limit: 2, lambda: 0.3)

      ids = Enum.map(result, & &1.id)
      # First pick is most relevant (id 1), second pick diversifies away from it (id 3)
      # lambda=0.3 weights diversity (0.7) more than relevance (0.3), so the near-duplicate id 2
      # gets penalized heavily while the orthogonal id 3 has zero similarity penalty
      assert ids == [1, 3]
    end

    test "with lambda=1.0 returns pure relevance order" do
      query = [1.0, 0.0, 0.0]

      candidates = [
        %{id: 1, embedding: [0.9, 0.1, 0.0]},
        %{id: 2, embedding: [0.85, 0.15, 0.0]},
        %{id: 3, embedding: [0.5, 0.5, 0.5]}
      ]

      result = MMR.rerank(query, candidates, limit: 3, lambda: 1.0)
      ids = Enum.map(result, & &1.id)
      assert ids == [1, 2, 3]
    end

    test "handles empty candidates" do
      assert [] == MMR.rerank([1.0, 0.0], [], limit: 5)
    end

    test "handles limit larger than candidates" do
      query = [1.0, 0.0]
      candidates = [%{id: 1, embedding: [0.9, 0.1]}]
      assert length(MMR.rerank(query, candidates, limit: 10)) == 1
    end
  end

  describe "cosine_similarity/2" do
    test "identical vectors return 1.0" do
      assert_in_delta MMR.cosine_similarity([1.0, 0.0], [1.0, 0.0]), 1.0, 0.001
    end

    test "orthogonal vectors return 0.0" do
      assert_in_delta MMR.cosine_similarity([1.0, 0.0], [0.0, 1.0]), 0.0, 0.001
    end
  end
end
