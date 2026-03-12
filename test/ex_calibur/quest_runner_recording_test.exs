defmodule ExCalibur.QuestRunner.RecordingTest do
  use ExCalibur.DataCase

  alias ExCalibur.Quests

  describe "run/2 recording" do
    test "creates a QuestRun record when a quest is executed" do
      {:ok, step} = Quests.create_step(%{name: "Recording Test Step", trigger: "manual", roster: []})

      {:ok, quest} =
        Quests.create_quest(%{
          name: "Recording Test Quest",
          trigger: "manual",
          steps: [%{"step_id" => step.id, "flow" => "always"}]
        })

      # Run the quest — step has empty roster so it returns {:ok, %{verdict: "pass", steps: []}}
      ExCalibur.QuestRunner.run(quest, "test input")

      # Verify a quest run was created
      runs = Quests.list_quest_runs(quest)
      assert runs != []
      run = List.first(runs)
      assert run.quest_id == quest.id
      assert run.status in ["complete", "failed"]
    end

    test "broadcasts quest_run_started and quest_run_completed events" do
      Phoenix.PubSub.subscribe(ExCalibur.PubSub, "quest_runs")

      {:ok, step} = Quests.create_step(%{name: "Broadcast Test Step", trigger: "manual", roster: []})

      {:ok, quest} =
        Quests.create_quest(%{
          name: "Broadcast Test Quest",
          trigger: "manual",
          steps: [%{"step_id" => step.id, "flow" => "always"}]
        })

      ExCalibur.QuestRunner.run(quest, "test input")

      assert_received {:quest_run_started, started_run}
      assert started_run.quest_id == quest.id
      assert started_run.status == "running"

      assert_received {:quest_run_completed, completed_run}
      assert completed_run.quest_id == quest.id
      assert completed_run.status in ["complete", "failed"]
    end
  end
end
