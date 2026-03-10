defmodule ExCalibur.QuestsTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Quests
  alias ExCalibur.Quests.Quest
  alias ExCalibur.Quests.Step

  describe "steps" do
    setup do
      ExCalibur.Repo.delete_all(Step)
      :ok
    end

    test "list_steps returns all steps" do
      {:ok, _} = Quests.create_step(%{name: "Test Step", trigger: "manual"})
      assert [%Step{}] = Quests.list_steps()
    end

    test "create_step with valid params" do
      assert {:ok, %Step{name: "My Step"}} =
               Quests.create_step(%{name: "My Step", trigger: "manual"})
    end

    test "create_step with invalid params" do
      assert {:error, %Ecto.Changeset{}} = Quests.create_step(%{})
    end

    test "update_step changes fields" do
      {:ok, step} = Quests.create_step(%{name: "Step A", trigger: "manual"})
      assert {:ok, %Step{status: "paused"}} = Quests.update_step(step, %{status: "paused"})
    end

    test "delete_step removes it" do
      {:ok, step} = Quests.create_step(%{name: "Step B", trigger: "manual"})
      assert {:ok, _} = Quests.delete_step(step)
      assert Quests.list_steps() == []
    end
  end

  describe "quests" do
    setup do
      ExCalibur.Repo.delete_all(Quest)
      :ok
    end

    test "list_quests returns all quests" do
      {:ok, _} = Quests.create_quest(%{name: "Quest A", trigger: "manual"})
      assert [%Quest{}] = Quests.list_quests()
    end

    test "create_quest with valid params" do
      assert {:ok, %Quest{name: "My Quest"}} =
               Quests.create_quest(%{name: "My Quest", trigger: "manual"})
    end

    test "list_quests_for_source returns active source-triggered quests" do
      {:ok, q1} =
        Quests.create_quest(%{
          name: "Quest Source",
          trigger: "source",
          source_ids: ["src-abc"],
          status: "active"
        })

      # Paused quest — should NOT appear
      {:ok, _q2} =
        Quests.create_quest(%{
          name: "Paused Quest",
          trigger: "source",
          source_ids: ["src-abc"],
          status: "paused"
        })

      # Different source — should NOT appear
      {:ok, _q3} =
        Quests.create_quest(%{
          name: "Other Quest",
          trigger: "source",
          source_ids: ["src-xyz"],
          status: "active"
        })

      assert [%Quest{id: id}] = Quests.list_quests_for_source("src-abc")
      assert id == q1.id
    end
  end
end
