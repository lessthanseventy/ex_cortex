defmodule ExCortex.Neuroplasticity.SeedTest do
  use ExCortex.DataCase

  alias ExCortex.Neuroplasticity.Seed

  test "seed creates thought, steps, and source" do
    assert {:ok, result} = Seed.seed(%{repo: "owner/repo"})
    assert result.thought
    assert result.source
    assert result.sweep_quest
    assert length(result.steps) == 6
  end

  test "seed creates source with correct config" do
    assert {:ok, %{source: source}} = Seed.seed(%{repo: "my-org/my-repo"})
    assert source.source_type == "github_issues"
    assert source.config["repo"] == "my-org/my-repo"
    assert source.config["label"] == "self-improvement"
  end

  test "seed creates thought triggered by source" do
    assert {:ok, %{thought: thought, source: source}} = Seed.seed(%{repo: "owner/repo"})
    assert thought.trigger == "source"
    assert to_string(source.id) in thought.source_ids
  end

  test "seed links all 6 steps to the thought in order" do
    assert {:ok, %{thought: thought, steps: steps}} = Seed.seed(%{repo: "owner/repo"})
    step_ids = Enum.map(steps, & &1.id)
    quest_step_ids = Enum.map(thought.steps, & &1["step_id"])
    assert Enum.sort(step_ids) == Enum.sort(quest_step_ids)
    orders = thought.steps |> Enum.map(& &1["order"]) |> Enum.sort()
    assert orders == [1, 2, 3, 4, 5, 6]
  end

  test "seed creates a scheduled sweep thought with 3 steps" do
    assert {:ok, %{sweep_quest: sweep_quest}} = Seed.seed(%{repo: "owner/repo"})
    assert sweep_quest.trigger == "scheduled"
    assert sweep_quest.schedule == "0 */4 * * *"
    assert length(sweep_quest.steps) == 3
    orders = sweep_quest.steps |> Enum.map(& &1["order"]) |> Enum.sort()
    assert orders == [1, 2, 3]
  end

  test "seed is idempotent — calling twice succeeds" do
    assert {:ok, _} = Seed.seed(%{repo: "owner/repo-1"})
    assert {:ok, _} = Seed.seed(%{repo: "owner/repo-2"})
  end
end
