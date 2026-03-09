defmodule ExCalibur.QuestsTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Quests
  alias ExCalibur.Quests.Campaign
  alias ExCalibur.Quests.Quest

  describe "quests" do
    setup do
      ExCalibur.Repo.delete_all(Quest)
      :ok
    end

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
    setup do
      ExCalibur.Repo.delete_all(Campaign)
      :ok
    end

    test "list_campaigns returns all campaigns" do
      {:ok, _} = Quests.create_campaign(%{name: "Campaign A", trigger: "manual"})
      assert [%Campaign{}] = Quests.list_campaigns()
    end

    test "create_campaign with valid params" do
      assert {:ok, %Campaign{name: "My Campaign"}} =
               Quests.create_campaign(%{name: "My Campaign", trigger: "manual"})
    end

    test "list_campaigns_for_source returns active source-triggered campaigns" do
      {:ok, c1} =
        Quests.create_campaign(%{
          name: "Campaign Source",
          trigger: "source",
          source_ids: ["src-abc"],
          status: "active"
        })

      # Paused campaign — should NOT appear
      {:ok, _c2} =
        Quests.create_campaign(%{
          name: "Paused Campaign",
          trigger: "source",
          source_ids: ["src-abc"],
          status: "paused"
        })

      # Different source — should NOT appear
      {:ok, _c3} =
        Quests.create_campaign(%{
          name: "Other Campaign",
          trigger: "source",
          source_ids: ["src-xyz"],
          status: "active"
        })

      assert [%Campaign{id: id}] = Quests.list_campaigns_for_source("src-abc")
      assert id == c1.id
    end
  end
end
