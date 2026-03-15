defmodule ExCortex.ContextProviders.ThoughtOutputTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.ContextProviders.ThoughtOutput
  alias ExCortex.Thoughts

  test "returns empty string when thought name not in config" do
    result = ThoughtOutput.build(%{"type" => "thought_output"}, %{}, "")
    assert result == ""
  end

  test "returns empty string when thought does not exist" do
    result = ThoughtOutput.build(%{"type" => "thought_output", "thought" => "Nonexistent Thought"}, %{}, "")
    assert result == ""
  end

  test "returns empty string when no completed runs exist" do
    {:ok, thought} =
      Thoughts.create_thought(%{name: "Test Thought #{System.unique_integer()}", trigger: "manual", steps: []})

    result = ThoughtOutput.build(%{"type" => "thought_output", "thought" => thought.name}, %{}, "")
    assert result == ""
  end

  test "injects step output from latest completed run" do
    {:ok, thought} =
      Thoughts.create_thought(%{name: "Output Thought #{System.unique_integer()}", trigger: "manual", steps: []})

    {:ok, _run} =
      Thoughts.create_daydream(%{
        thought_id: thought.id,
        status: "complete",
        synapse_results: %{"0" => %{"data" => "Health scan findings here", "status" => "ok"}}
      })

    result = ThoughtOutput.build(%{"type" => "thought_output", "thought" => thought.name}, %{}, "")
    assert result =~ thought.name
    assert result =~ "Health scan findings here"
    assert result =~ "Synapse 0"
  end

  test "filters to specified step indices" do
    {:ok, thought} =
      Thoughts.create_thought(%{name: "Multi-Step Thought #{System.unique_integer()}", trigger: "manual", steps: []})

    {:ok, _run} =
      Thoughts.create_daydream(%{
        thought_id: thought.id,
        status: "complete",
        synapse_results: %{
          "0" => %{"data" => "Step zero output", "status" => "ok"},
          "1" => %{"data" => "Step one output", "status" => "ok"}
        }
      })

    result = ThoughtOutput.build(%{"type" => "thought_output", "thought" => thought.name, "steps" => [1]}, %{}, "")
    refute result =~ "Step zero output"
    assert result =~ "Step one output"
  end

  test "truncates long step output" do
    long_output = String.duplicate("x", 5_000)

    {:ok, thought} =
      Thoughts.create_thought(%{name: "Long Thought #{System.unique_integer()}", trigger: "manual", steps: []})

    {:ok, _run} =
      Thoughts.create_daydream(%{
        thought_id: thought.id,
        status: "complete",
        synapse_results: %{"0" => %{"data" => long_output, "status" => "ok"}}
      })

    result =
      ThoughtOutput.build(%{"type" => "thought_output", "thought" => thought.name, "max_bytes_per_step" => 100}, %{}, "")

    assert result =~ "(truncated)"
  end
end
