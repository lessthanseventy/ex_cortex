defmodule ExCortex.Neuroplasticity.SeedTest do
  use ExCortex.DataCase

  alias ExCortex.Neuroplasticity.Seed

  test "seed creates rumination, steps, and source" do
    assert {:ok, result} = Seed.seed(%{repo: "owner/repo"})
    assert result.rumination
    assert result.source
    assert result.sweep_rumination
    assert length(result.steps) == 7
  end

  test "seed creates source with correct config" do
    assert {:ok, %{source: source}} = Seed.seed(%{repo: "my-org/my-repo"})
    assert source.source_type == "github_issues"
    assert source.config["repo"] == "my-org/my-repo"
    assert source.config["label"] == "self-improvement"
  end

  test "seed creates rumination triggered by source" do
    assert {:ok, %{rumination: rumination, source: source}} = Seed.seed(%{repo: "owner/repo"})
    assert rumination.trigger == "source"
    assert to_string(source.id) in rumination.source_ids
  end

  test "seed links all 7 steps to the rumination in order" do
    assert {:ok, %{rumination: rumination, steps: steps}} = Seed.seed(%{repo: "owner/repo"})
    step_ids = Enum.map(steps, & &1.id)
    rumination_step_ids = Enum.map(rumination.steps, & &1["step_id"])
    assert Enum.sort(step_ids) == Enum.sort(rumination_step_ids)
    orders = rumination.steps |> Enum.map(& &1["order"]) |> Enum.sort()
    assert orders == [1, 2, 3, 4, 5, 6, 7]
  end

  test "seed creates a scheduled sweep rumination with 3 steps" do
    assert {:ok, %{sweep_rumination: sweep_rumination}} = Seed.seed(%{repo: "owner/repo"})
    assert sweep_rumination.trigger == "scheduled"
    assert sweep_rumination.schedule == "0 */4 * * *"
    assert length(sweep_rumination.steps) == 3
    orders = sweep_rumination.steps |> Enum.map(& &1["order"]) |> Enum.sort()
    assert orders == [1, 2, 3]
  end

  test "seed is idempotent — calling twice succeeds" do
    assert {:ok, _} = Seed.seed(%{repo: "owner/repo-1"})
    assert {:ok, _} = Seed.seed(%{repo: "owner/repo-2"})
  end
end
