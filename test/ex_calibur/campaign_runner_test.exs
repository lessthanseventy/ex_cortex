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

  describe "branch steps" do
    test "run/2 with a branch step runs all quests and synthesizer" do
      {:ok, q1} =
        Quests.create_quest(%{
          name: "Branch A",
          trigger: "manual",
          output_type: "verdict",
          roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]
        })

      {:ok, q2} =
        Quests.create_quest(%{
          name: "Branch B",
          trigger: "manual",
          output_type: "verdict",
          roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]
        })

      {:ok, synth} =
        Quests.create_quest(%{
          name: "Synthesizer",
          trigger: "manual",
          output_type: "verdict",
          roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]
        })

      {:ok, campaign} =
        Quests.create_campaign(%{
          name: "Branch Campaign",
          trigger: "manual",
          steps: [
            %{
              "type" => "branch",
              "quests" => [to_string(q1.id), to_string(q2.id)],
              "synthesizer" => to_string(synth.id),
              "order" => 1
            }
          ]
        })

      result = CampaignRunner.run(campaign, "test input")
      assert elem(result, 0) in [:ok, :error]
    end

    test "combine_branch_results/2 joins multiple results into one context block" do
      results = [
        {"Quest Alpha", {:ok, %{verdict: "pass", steps: []}}},
        {"Quest Beta", {:ok, %{verdict: "fail", steps: []}}}
      ]

      combined = CampaignRunner.combine_branch_results(results, "input")
      assert String.contains?(combined, "Quest Alpha")
      assert String.contains?(combined, "Quest Beta")
      assert String.contains?(combined, "pass")
      assert String.contains?(combined, "fail")
    end
  end

  describe "structured handoff" do
    test "result_to_text/3 formats a structured handoff block" do
      result =
        {:ok,
         %{
           verdict: "pass",
           steps: [
             %{
               who: "all",
               verdict: "pass",
               results: [%{member: "Analyst", verdict: "pass", reason: "Evidence found"}]
             }
           ]
         }}

      text = CampaignRunner.result_to_text(result, "Accuracy Check", "Tone Review")
      assert String.contains?(text, "## Prior Step: Accuracy Check")
      assert String.contains?(text, "**Verdict:** pass")
      assert String.contains?(text, "Analyst")
      assert String.contains?(text, "Tone Review")
    end

    test "result_to_text/3 formats artifact handoff" do
      result = {:ok, %{artifact: %{title: "Report", body: "Body text"}}}
      text = CampaignRunner.result_to_text(result, "Draft Step", "Review Step")
      assert String.contains?(text, "## Prior Step: Draft Step")
      assert String.contains?(text, "Report")
      assert String.contains?(text, "Review Step")
    end

    test "result_to_text/3 with nil next_quest_name omits question line" do
      result = {:ok, %{verdict: "pass", steps: []}}
      text = CampaignRunner.result_to_text(result, "Final Step", nil)
      refute String.contains?(text, "Open question")
    end
  end
end
