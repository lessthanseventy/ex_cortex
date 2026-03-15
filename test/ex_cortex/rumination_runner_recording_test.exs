defmodule ExCortex.Ruminations.Runner.RecordingTest do
  use ExCortex.DataCase

  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Runner

  describe "run/2 recording" do
    test "creates a Daydream record when a rumination is executed" do
      {:ok, step} = Ruminations.create_synapse(%{name: "Recording Test Step", trigger: "manual", roster: []})

      {:ok, rumination} =
        Ruminations.create_rumination(%{
          name: "Recording Test Rumination",
          trigger: "manual",
          steps: [%{"step_id" => step.id, "flow" => "always"}]
        })

      # Run the rumination — step has empty roster so it returns {:ok, %{verdict: "pass", steps: []}}
      Runner.run(rumination, "test input")

      # Verify a daydream was created
      runs = Ruminations.list_daydreams(rumination)
      assert runs != []
      run = List.first(runs)
      assert run.rumination_id == rumination.id
      assert run.status in ["complete", "failed"]
    end

    test "broadcasts daydream_started and daydream_completed events" do
      Phoenix.PubSub.subscribe(ExCortex.PubSub, "daydreams")

      {:ok, step} = Ruminations.create_synapse(%{name: "Broadcast Test Step", trigger: "manual", roster: []})

      {:ok, rumination} =
        Ruminations.create_rumination(%{
          name: "Broadcast Test Rumination",
          trigger: "manual",
          steps: [%{"step_id" => step.id, "flow" => "always"}]
        })

      Runner.run(rumination, "test input")

      assert_received {:daydream_started, started_run}
      assert started_run.rumination_id == rumination.id
      assert started_run.status == "running"

      assert_received {:daydream_completed, completed_run}
      assert completed_run.rumination_id == rumination.id
      assert completed_run.status in ["complete", "failed"]
    end
  end
end
