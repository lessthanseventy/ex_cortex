defmodule ExCalibur.ContextProviders.QuestOutputTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.ContextProviders.QuestOutput
  alias ExCalibur.Quests

  test "returns empty string when quest name not in config" do
    result = QuestOutput.build(%{"type" => "quest_output"}, %{}, "")
    assert result == ""
  end

  test "returns empty string when quest does not exist" do
    result = QuestOutput.build(%{"type" => "quest_output", "quest" => "Nonexistent Quest"}, %{}, "")
    assert result == ""
  end

  test "returns empty string when no completed runs exist" do
    {:ok, quest} =
      Quests.create_quest(%{name: "Test Quest #{System.unique_integer()}", trigger: "manual", steps: []})

    result = QuestOutput.build(%{"type" => "quest_output", "quest" => quest.name}, %{}, "")
    assert result == ""
  end

  test "injects step output from latest completed run" do
    {:ok, quest} =
      Quests.create_quest(%{name: "Output Quest #{System.unique_integer()}", trigger: "manual", steps: []})

    {:ok, _run} =
      Quests.create_quest_run(%{
        quest_id: quest.id,
        status: "complete",
        step_results: %{"0" => %{"data" => "Health scan findings here", "status" => "ok"}}
      })

    result = QuestOutput.build(%{"type" => "quest_output", "quest" => quest.name}, %{}, "")
    assert result =~ quest.name
    assert result =~ "Health scan findings here"
    assert result =~ "Step 0"
  end

  test "filters to specified step indices" do
    {:ok, quest} =
      Quests.create_quest(%{name: "Multi-Step Quest #{System.unique_integer()}", trigger: "manual", steps: []})

    {:ok, _run} =
      Quests.create_quest_run(%{
        quest_id: quest.id,
        status: "complete",
        step_results: %{
          "0" => %{"data" => "Step zero output", "status" => "ok"},
          "1" => %{"data" => "Step one output", "status" => "ok"}
        }
      })

    result = QuestOutput.build(%{"type" => "quest_output", "quest" => quest.name, "steps" => [1]}, %{}, "")
    refute result =~ "Step zero output"
    assert result =~ "Step one output"
  end

  test "truncates long step output" do
    long_output = String.duplicate("x", 5_000)

    {:ok, quest} =
      Quests.create_quest(%{name: "Long Quest #{System.unique_integer()}", trigger: "manual", steps: []})

    {:ok, _run} =
      Quests.create_quest_run(%{
        quest_id: quest.id,
        status: "complete",
        step_results: %{"0" => %{"data" => long_output, "status" => "ok"}}
      })

    result = QuestOutput.build(%{"type" => "quest_output", "quest" => quest.name, "max_bytes_per_step" => 100}, %{}, "")
    assert result =~ "(truncated)"
  end
end
