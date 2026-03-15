defmodule ExCortex.ClustersTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Clusters

  test "upsert_charter/2 creates a pathway for a cluster" do
    assert {:ok, pathway} = Clusters.upsert_charter("TestGuild", "Our values: honesty.")
    assert pathway.guild_name == "TestGuild"
    assert pathway.charter_text == "Our values: honesty."
  end

  test "upsert_charter/2 updates an existing pathway" do
    {:ok, _} = Clusters.upsert_charter("TestGuild", "v1")
    {:ok, updated} = Clusters.upsert_charter("TestGuild", "v2")
    assert updated.charter_text == "v2"
  end

  test "get_charter/1 returns nil when no pathway exists" do
    assert Clusters.get_charter("NoSuchGuild") == nil
  end

  test "get_charter/1 returns pathway text when it exists" do
    {:ok, _} = Clusters.upsert_charter("MyGuild", "Be excellent.")
    assert Clusters.get_charter("MyGuild") == "Be excellent."
  end
end
