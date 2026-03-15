defmodule ExCortex.ContextProviders.RuminationOutputTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.ContextProviders.RuminationOutput
  alias ExCortex.Ruminations

  test "returns empty string when rumination name not in config" do
    result = RuminationOutput.build(%{"type" => "rumination_output"}, %{}, "")
    assert result == ""
  end

  test "returns empty string when rumination does not exist" do
    result = RuminationOutput.build(%{"type" => "rumination_output", "rumination" => "Nonexistent Rumination"}, %{}, "")
    assert result == ""
  end

  test "returns empty string when no completed runs exist" do
    {:ok, rumination} =
      Ruminations.create_rumination(%{name: "Test Rumination #{System.unique_integer()}", trigger: "manual", steps: []})

    result = RuminationOutput.build(%{"type" => "rumination_output", "rumination" => rumination.name}, %{}, "")
    assert result == ""
  end

  test "injects step output from latest completed run" do
    {:ok, rumination} =
      Ruminations.create_rumination(%{name: "Output Rumination #{System.unique_integer()}", trigger: "manual", steps: []})

    {:ok, _run} =
      Ruminations.create_daydream(%{
        rumination_id: rumination.id,
        status: "complete",
        synapse_results: %{"0" => %{"data" => "Health scan findings here", "status" => "ok"}}
      })

    result = RuminationOutput.build(%{"type" => "rumination_output", "rumination" => rumination.name}, %{}, "")
    assert result =~ rumination.name
    assert result =~ "Health scan findings here"
    assert result =~ "Synapse 0"
  end

  test "filters to specified step indices" do
    {:ok, rumination} =
      Ruminations.create_rumination(%{name: "Multi-Step Rumination #{System.unique_integer()}", trigger: "manual", steps: []})

    {:ok, _run} =
      Ruminations.create_daydream(%{
        rumination_id: rumination.id,
        status: "complete",
        synapse_results: %{
          "0" => %{"data" => "Step zero output", "status" => "ok"},
          "1" => %{"data" => "Step one output", "status" => "ok"}
        }
      })

    result = RuminationOutput.build(%{"type" => "rumination_output", "rumination" => rumination.name, "steps" => [1]}, %{}, "")
    refute result =~ "Step zero output"
    assert result =~ "Step one output"
  end

  test "truncates long step output" do
    long_output = String.duplicate("x", 5_000)

    {:ok, rumination} =
      Ruminations.create_rumination(%{name: "Long Rumination #{System.unique_integer()}", trigger: "manual", steps: []})

    {:ok, _run} =
      Ruminations.create_daydream(%{
        rumination_id: rumination.id,
        status: "complete",
        synapse_results: %{"0" => %{"data" => long_output, "status" => "ok"}}
      })

    result =
      RuminationOutput.build(%{"type" => "rumination_output", "rumination" => rumination.name, "max_bytes_per_step" => 100}, %{}, "")

    assert result =~ "(truncated)"
  end
end
