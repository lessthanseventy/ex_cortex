defmodule ExCalibur.QuestRunner.GuardrailsIntegrationTest do
  use ExCalibur.DataCase, async: false

  alias ExCalibur.LLM.Ollama
  alias ExCalibur.QuestRunner
  alias ExCalibur.Quests
  alias ExCalibur.StepRunner

  describe "verdict gate integration" do
    test "quest with gated step that fails is detected by check_gate" do
      {:ok, gate_step} =
        Quests.create_step(%{
          name: "Test Gate Step",
          trigger: "manual",
          output_type: "verdict",
          roster: []
        })

      result = {:ok, %{verdict: "fail", steps: [%{results: [%{reason: "bad code"}]}]}}
      step_entry = %{"step_id" => to_string(gate_step.id), "order" => 1, "gate" => true}

      assert {:gated, reason} = QuestRunner.check_gate(step_entry, result)
      assert reason =~ "bad code"
    end

    test "check_gate returns :continue for passing step" do
      result = {:ok, %{verdict: "pass", steps: [%{results: [%{reason: "looks good"}]}]}}
      step_entry = %{"step_id" => "1", "order" => 1, "gate" => true}

      assert :continue = QuestRunner.check_gate(step_entry, result)
    end

    test "check_gate returns :continue for non-gated step even on fail" do
      result = {:ok, %{verdict: "fail", steps: [%{results: [%{reason: "bad"}]}]}}
      step_entry = %{"step_id" => "1", "order" => 1}

      assert :continue = QuestRunner.check_gate(step_entry, result)
    end
  end

  describe "circuit breaker" do
    test "empty_result? detects empty strings" do
      assert Ollama.empty_result?("")
      assert Ollama.empty_result?("[]")
      assert Ollama.empty_result?("[]\n")
      assert Ollama.empty_result?("Error: something went wrong")
      refute Ollama.empty_result?("some actual content")
    end

    test "check_circuit_breaker trips after 3 consecutive empties" do
      bs = %{}
      {:ok, bs} = Ollama.check_circuit_breaker("search", "", bs)
      assert bs["search"] == 1

      {:ok, bs} = Ollama.check_circuit_breaker("search", "", bs)
      assert bs["search"] == 2

      {:tripped, bs} = Ollama.check_circuit_breaker("search", "", bs)
      assert bs["search"] == 3
    end

    test "check_circuit_breaker resets on non-empty result" do
      bs = %{"search" => 2}
      {:ok, bs} = Ollama.check_circuit_breaker("search", "found something", bs)
      assert bs["search"] == 0
    end
  end

  describe "dangerous tool detection" do
    test "dangerous? identifies dangerous tools" do
      assert StepRunner.dangerous?("close_issue")
      assert StepRunner.dangerous?("merge_pr")
      assert StepRunner.dangerous?("send_email")
      assert StepRunner.dangerous?("create_github_issue")
    end

    test "dangerous? rejects safe tools" do
      refute StepRunner.dangerous?("read_file")
      refute StepRunner.dangerous?("run_sandbox")
      refute StepRunner.dangerous?("query_lore")
    end
  end

  describe "write tool detection for rollback" do
    test "has_write_tools? detects write tools" do
      assert StepRunner.has_write_tools?(["write_file", "read_file"])
      assert StepRunner.has_write_tools?(["git_commit"])
      assert StepRunner.has_write_tools?(["edit_file"])
    end

    test "has_write_tools? returns false for read-only tools" do
      refute StepRunner.has_write_tools?(["read_file", "run_sandbox"])
      refute StepRunner.has_write_tools?([])
      refute StepRunner.has_write_tools?(nil)
    end
  end

  describe "step schema guardrail fields" do
    test "step accepts dangerous_tool_mode" do
      {:ok, step} =
        Quests.create_step(%{
          name: "Guarded Step",
          trigger: "manual",
          output_type: "freeform",
          dangerous_tool_mode: "intercept",
          max_tool_iterations: 10,
          roster: []
        })

      assert step.dangerous_tool_mode == "intercept"
      assert step.max_tool_iterations == 10
    end

    test "step defaults dangerous_tool_mode to execute" do
      {:ok, step} =
        Quests.create_step(%{
          name: "Default Step",
          trigger: "manual",
          output_type: "freeform",
          roster: []
        })

      assert step.dangerous_tool_mode == "execute"
      assert step.max_tool_iterations == 15
    end

    test "step rejects invalid dangerous_tool_mode" do
      {:error, changeset} =
        Quests.create_step(%{
          name: "Bad Step",
          trigger: "manual",
          output_type: "freeform",
          dangerous_tool_mode: "yolo",
          roster: []
        })

      assert errors_on(changeset).dangerous_tool_mode != []
    end
  end
end
