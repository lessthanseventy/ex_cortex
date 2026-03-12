defmodule ExCalibur.LearningLoopTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.LearningLoop

  test "retrospect returns empty list when Claude not configured" do
    step = %ExCalibur.Quests.Step{
      id: 1,
      name: "test step",
      trigger: "manual",
      roster: [],
      context_providers: [],
      source_ids: [],
      lore_tags: [],
      escalate_on_verdict: [],
      reflect_on_verdict: [],
      loop_tools: []
    }

    step_run = %{id: 1, results: %{}, input: "test input"}
    assert {:ok, []} = LearningLoop.retrospect(step, step_run)
  end
end
