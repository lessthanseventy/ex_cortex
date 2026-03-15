defmodule ExCortex.MemoryTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Memory

  describe "query/2 with tiered loading" do
    setup do
      {:ok, engram} =
        Memory.create_engram(%{
          title: "API auth patterns",
          body: "Full detailed content about OAuth2, JWT, and API keys...",
          impression: "API authentication guide covering OAuth 2.0, JWT, API keys",
          recall: "# Auth Guide\n## OAuth 2.0\nRecommended for user-facing...\n## JWT\nFor service-to-service...",
          category: "semantic",
          tags: ["api", "auth"],
          importance: 4
        })

      %{engram: engram}
    end

    test "returns L0 impressions for initial search", %{engram: engram} do
      results = Memory.query("auth", tier: :L0)
      assert length(results) > 0
      result = hd(results)
      assert result.id == engram.id
      assert result.impression
      refute result.body =~ "Full detailed"
    end

    test "returns L1 recall for search", %{engram: engram} do
      results = Memory.query("auth", tier: :L1)
      result = hd(results)
      assert result.id == engram.id
      assert result.recall =~ "OAuth 2.0"
      refute result.body =~ "Full detailed"
    end

    test "loads L1 recall for selected engram", %{engram: engram} do
      result = Memory.load_recall(engram.id)
      assert result.recall =~ "OAuth 2.0"
      refute result.body =~ "Full detailed"
    end

    test "loads L2 deep content on demand", %{engram: engram} do
      result = Memory.load_deep(engram.id)
      assert result.body =~ "Full detailed content"
    end

    test "searches by tag", %{engram: engram} do
      results = Memory.query("api", tier: :L0)
      assert Enum.any?(results, &(&1.id == engram.id))
    end
  end

  describe "create_engram/1" do
    test "creates with category" do
      {:ok, engram} =
        Memory.create_engram(%{
          title: "Test event",
          body: "Something happened",
          category: "episodic",
          source: "thought"
        })

      assert engram.category == "episodic"
    end
  end

  describe "recall paths" do
    test "logs and retrieves recall paths" do
      {:ok, thought} =
        ExCortex.Thoughts.create_thought(%{name: "Recall Test", trigger: "manual", steps: []})

      {:ok, daydream} =
        ExCortex.Thoughts.create_daydream(%{thought_id: thought.id, status: "running"})

      {:ok, engram} = Memory.create_engram(%{title: "Recall target", body: "details"})

      {:ok, _rp} =
        Memory.log_recall(%{
          daydream_id: daydream.id,
          engram_id: engram.id,
          reason: "Relevant to auth question",
          tier_accessed: "L1",
          step: 0
        })

      paths = Memory.recall_paths_for_daydream(daydream.id)
      assert length(paths) == 1
      assert hd(paths).engram_title == "Recall target"
    end
  end
end
