defmodule ExCellenceServer.QuestsTest do
  use ExCellenceServer.DataCase, async: true

  alias ExCellenceServer.Quests
  alias ExCellenceServer.Quests.Campaign
  alias ExCellenceServer.Quests.Quest

  describe "quests" do
    test "list_quests returns all quests" do
      {:ok, _} = Quests.create_quest(%{name: "Test Quest", trigger: "manual"})
      assert [%Quest{}] = Quests.list_quests()
    end

    test "create_quest with valid params" do
      assert {:ok, %Quest{name: "My Quest"}} =
               Quests.create_quest(%{name: "My Quest", trigger: "manual"})
    end

    test "create_quest with invalid params" do
      assert {:error, %Ecto.Changeset{}} = Quests.create_quest(%{})
    end

    test "update_quest changes fields" do
      {:ok, quest} = Quests.create_quest(%{name: "Quest A", trigger: "manual"})
      assert {:ok, %Quest{status: "paused"}} = Quests.update_quest(quest, %{status: "paused"})
    end

    test "delete_quest removes it" do
      {:ok, quest} = Quests.create_quest(%{name: "Quest B", trigger: "manual"})
      assert {:ok, _} = Quests.delete_quest(quest)
      assert Quests.list_quests() == []
    end
  end

  describe "campaigns" do
    test "list_campaigns returns all campaigns" do
      {:ok, _} = Quests.create_campaign(%{name: "Campaign A", trigger: "manual"})
      assert [%Campaign{}] = Quests.list_campaigns()
    end

    test "create_campaign with valid params" do
      assert {:ok, %Campaign{name: "My Campaign"}} =
               Quests.create_campaign(%{name: "My Campaign", trigger: "manual"})
    end
  end
end
