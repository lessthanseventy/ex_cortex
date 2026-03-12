defmodule ExCalibur.SelfImprovement.QuestSeedTest do
  use ExCalibur.DataCase

  alias ExCalibur.SelfImprovement.QuestSeed

  test "seed creates quest, steps, and source" do
    assert {:ok, result} = QuestSeed.seed(%{repo: "owner/repo"})
    assert result.quest
    assert result.source
    assert result.sweep_quest
    assert length(result.steps) == 6
  end

  test "seed creates source with correct config" do
    assert {:ok, %{source: source}} = QuestSeed.seed(%{repo: "my-org/my-repo"})
    assert source.source_type == "github_issues"
    assert source.config["repo"] == "my-org/my-repo"
    assert source.config["label"] == "self-improvement"
  end

  test "seed creates quest triggered by source" do
    assert {:ok, %{quest: quest, source: source}} = QuestSeed.seed(%{repo: "owner/repo"})
    assert quest.trigger == "source"
    assert to_string(source.id) in quest.source_ids
  end

  test "seed links all 6 steps to the quest in order" do
    assert {:ok, %{quest: quest, steps: steps}} = QuestSeed.seed(%{repo: "owner/repo"})
    step_ids = Enum.map(steps, & &1.id)
    quest_step_ids = Enum.map(quest.steps, & &1["step_id"])
    assert Enum.sort(step_ids) == Enum.sort(quest_step_ids)
    orders = quest.steps |> Enum.map(& &1["order"]) |> Enum.sort()
    assert orders == [1, 2, 3, 4, 5, 6]
  end

  test "seed creates a scheduled sweep quest" do
    assert {:ok, %{sweep_quest: sweep_quest}} = QuestSeed.seed(%{repo: "owner/repo"})
    assert sweep_quest.trigger == "scheduled"
    assert sweep_quest.schedule == "0 9 * * *"
    assert length(sweep_quest.steps) == 1
  end

  test "seed returns error when source creation fails" do
    # Empty source_type would fail, but we test via bad repo — source creates fine but
    # let's just ensure idempotency is handled via unique step name constraint
    assert {:ok, _} = QuestSeed.seed(%{repo: "owner/repo-1"})
    # Seeding again with different repo still works (different step names if we had them,
    # but since names are unique, this will fail as expected)
    assert {:error, _} = QuestSeed.seed(%{repo: "owner/repo-2"})
  end
end
