defmodule ExCortex.ClusterPathwaysTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Clusters

  test "upsert_pathway/2 creates a pathway for a cluster" do
    assert {:ok, pathway} = Clusters.upsert_pathway("TestCluster", "Our values: honesty.")
    assert pathway.cluster_name == "TestCluster"
    assert pathway.pathway_text == "Our values: honesty."
  end

  test "upsert_pathway/2 updates an existing pathway" do
    {:ok, _} = Clusters.upsert_pathway("TestCluster", "v1")
    {:ok, updated} = Clusters.upsert_pathway("TestCluster", "v2")
    assert updated.pathway_text == "v2"
  end

  test "get_pathway/1 returns nil when no pathway exists" do
    assert Clusters.get_pathway("NoSuchCluster") == nil
  end

  test "get_pathway/1 returns pathway text when it exists" do
    {:ok, _} = Clusters.upsert_pathway("MyCluster", "Be excellent.")
    assert Clusters.get_pathway("MyCluster") == "Be excellent."
  end
end
