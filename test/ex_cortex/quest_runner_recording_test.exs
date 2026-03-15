defmodule ExCortex.Thoughts.Runner.RecordingTest do
  use ExCortex.DataCase

  alias ExCortex.Thoughts
  alias ExCortex.Thoughts.Runner

  describe "run/2 recording" do
    test "creates a QuestRun record when a thought is executed" do
      {:ok, step} = Thoughts.create_synapse(%{name: "Recording Test Step", trigger: "manual", roster: []})

      {:ok, thought} =
        Thoughts.create_thought(%{
          name: "Recording Test Thought",
          trigger: "manual",
          steps: [%{"step_id" => step.id, "flow" => "always"}]
        })

      # Run the thought — step has empty roster so it returns {:ok, %{verdict: "pass", steps: []}}
      Runner.run(thought, "test input")

      # Verify a daydream was created
      runs = Thoughts.list_daydreams(thought)
      assert runs != []
      run = List.first(runs)
      assert run.thought_id == thought.id
      assert run.status in ["complete", "failed"]
    end

    test "broadcasts quest_run_started and quest_run_completed events" do
      Phoenix.PubSub.subscribe(ExCortex.PubSub, "daydreams")

      {:ok, step} = Thoughts.create_synapse(%{name: "Broadcast Test Step", trigger: "manual", roster: []})

      {:ok, thought} =
        Thoughts.create_thought(%{
          name: "Broadcast Test Thought",
          trigger: "manual",
          steps: [%{"step_id" => step.id, "flow" => "always"}]
        })

      Runner.run(thought, "test input")

      assert_received {:daydream_started, started_run}
      assert started_run.thought_id == thought.id
      assert started_run.status == "running"

      assert_received {:daydream_completed, completed_run}
      assert completed_run.thought_id == thought.id
      assert completed_run.status in ["complete", "failed"]
    end
  end
end
