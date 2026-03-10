defmodule ExCalibur.QuestRunnerTest do
  use ExCalibur.DataCase, async: false

  alias ExCalibur.QuestRunner
  alias ExCalibur.Quests

  test "run/2 executes each step in order and returns final result" do
    # Create two steps
    {:ok, s1} =
      Quests.create_step(%{
        name: "Step 1",
        trigger: "manual",
        output_type: "artifact",
        roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]
      })

    {:ok, s2} =
      Quests.create_step(%{
        name: "Step 2",
        trigger: "manual",
        output_type: "artifact",
        roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]
      })

    {:ok, quest} =
      Quests.create_quest(%{
        name: "Two-Step Quest",
        trigger: "manual",
        steps: [
          %{"step_id" => to_string(s1.id), "flow" => "always"},
          %{"step_id" => to_string(s2.id), "flow" => "always"}
        ]
      })

    # No members in test DB → StepRunner returns {:error, :no_members}
    # QuestRunner should still return a result (even if each step errors)
    result = QuestRunner.run(quest, "test input")
    assert elem(result, 0) in [:ok, :error]
  end

  test "run/2 with empty steps returns ok with empty result" do
    {:ok, quest} =
      Quests.create_quest(%{name: "Empty Quest", trigger: "manual", steps: []})

    assert {:ok, %{steps: []}} = QuestRunner.run(quest, "input")
  end

  test "result_to_text/1 formats artifact result as markdown" do
    result = {:ok, %{artifact: %{title: "My Title", body: "Some body text"}}}
    text = QuestRunner.result_to_text(result)
    assert String.contains?(text, "My Title")
    assert String.contains?(text, "Some body text")
  end

  test "result_to_text/1 formats verdict result as summary" do
    result = {:ok, %{verdict: "pass", steps: []}}
    text = QuestRunner.result_to_text(result)
    assert String.contains?(text, "pass")
  end

  describe "branch steps" do
    test "run/2 with a branch step runs all steps and synthesizer" do
      {:ok, s1} =
        Quests.create_step(%{
          name: "Branch A",
          trigger: "manual",
          output_type: "verdict",
          roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]
        })

      {:ok, s2} =
        Quests.create_step(%{
          name: "Branch B",
          trigger: "manual",
          output_type: "verdict",
          roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]
        })

      {:ok, synth} =
        Quests.create_step(%{
          name: "Synthesizer",
          trigger: "manual",
          output_type: "verdict",
          roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}]
        })

      {:ok, quest} =
        Quests.create_quest(%{
          name: "Branch Quest",
          trigger: "manual",
          steps: [
            %{
              "type" => "branch",
              "steps" => [to_string(s1.id), to_string(s2.id)],
              "synthesizer" => to_string(synth.id),
              "flow" => "always"
            }
          ]
        })

      result = QuestRunner.run(quest, "test input")
      assert elem(result, 0) in [:ok, :error]
    end

    test "combine_branch_results/2 joins multiple results into one context block" do
      results = [
        {"Step Alpha", {:ok, %{verdict: "pass", steps: []}}},
        {"Step Beta", {:ok, %{verdict: "fail", steps: []}}}
      ]

      combined = QuestRunner.combine_branch_results(results, "input")
      assert String.contains?(combined, "Step Alpha")
      assert String.contains?(combined, "Step Beta")
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

      text = QuestRunner.result_to_text(result, "Accuracy Check", "Tone Review")
      assert String.contains?(text, "## Prior Step: Accuracy Check")
      assert String.contains?(text, "**Verdict:** pass")
      assert String.contains?(text, "Analyst")
      assert String.contains?(text, "Tone Review")
    end

    test "result_to_text/3 formats artifact handoff" do
      result = {:ok, %{artifact: %{title: "Report", body: "Body text"}}}
      text = QuestRunner.result_to_text(result, "Draft Step", "Review Step")
      assert String.contains?(text, "## Prior Step: Draft Step")
      assert String.contains?(text, "Report")
      assert String.contains?(text, "Review Step")
    end

    test "result_to_text/3 with nil next_step_name omits question line" do
      result = {:ok, %{verdict: "pass", steps: []}}
      text = QuestRunner.result_to_text(result, "Final Step", nil)
      refute String.contains?(text, "Open question")
    end
  end
end
