defmodule ExCortex.Neuroplasticity.LoopTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Neuroplasticity.Loop

  test "retrospect returns empty list when Claude not configured" do
    step = %ExCortex.Thoughts.Synapse{
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
    assert {:ok, []} = Loop.retrospect(step, step_run)
  end
end
