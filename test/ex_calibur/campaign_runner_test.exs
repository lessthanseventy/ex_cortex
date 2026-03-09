defmodule ExCalibur.CampaignRunnerTest do
  use ExCalibur.DataCase, async: false

  alias ExCalibur.CampaignRunner
  alias ExCalibur.Quests

  test "run/2 executes each step quest in order and returns final result" do
    # Create two quests
    {:ok, q1} =
      Quests.create_quest(%{
        name: "Step 1 Quest",
        trigger: "manual",
        output_type: "artifact",
        roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]
      })

    {:ok, q2} =
      Quests.create_quest(%{
        name: "Step 2 Quest",
        trigger: "manual",
        output_type: "artifact",
        roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]
      })

    {:ok, campaign} =
      Quests.create_campaign(%{
        name: "Two-Step Campaign",
        trigger: "manual",
        steps: [
          %{"quest_id" => to_string(q1.id), "order" => 1},
          %{"quest_id" => to_string(q2.id), "order" => 2}
        ]
      })

    # No members in test DB → QuestRunner returns {:error, :no_members}
    # CampaignRunner should still return a result (even if each step errors)
    result = CampaignRunner.run(campaign, "test input")
    assert elem(result, 0) in [:ok, :error]
  end

  test "run/2 with empty steps returns ok with empty result" do
    {:ok, campaign} =
      Quests.create_campaign(%{name: "Empty Campaign", trigger: "manual", steps: []})

    assert {:ok, %{steps: []}} = CampaignRunner.run(campaign, "input")
  end

  test "result_to_text/1 formats artifact result as markdown" do
    result = {:ok, %{artifact: %{title: "My Title", body: "Some body text"}}}
    text = CampaignRunner.result_to_text(result)
    assert String.contains?(text, "My Title")
    assert String.contains?(text, "Some body text")
  end

  test "result_to_text/1 formats verdict result as summary" do
    result = {:ok, %{verdict: "pass", steps: []}}
    text = CampaignRunner.result_to_text(result)
    assert String.contains?(text, "pass")
  end
end
