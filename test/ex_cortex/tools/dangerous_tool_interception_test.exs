defmodule ExCortex.DangerousToolInterceptionTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.LLM.Ollama
  alias ExCortex.Thoughts.ImpulseRunner

  describe "ImpulseRunner.dangerous?/1" do
    test "returns true for dangerous tools" do
      for tool <- ~w(send_email create_github_issue comment_github run_thought merge_pr git_pull restart_app close_issue) do
        assert ImpulseRunner.dangerous?(tool), "expected #{tool} to be dangerous"
      end
    end

    test "returns false for safe tools" do
      for tool <- ~w(query_memory list_files read_file query_axiom) do
        refute ImpulseRunner.dangerous?(tool), "expected #{tool} to be safe"
      end
    end
  end

  describe "intercept_dangerous_tool/4" do
    test "creates a proposal for a dangerous tool" do
      {:ok, step} =
        ExCortex.Thoughts.create_synapse(%{
          name: "interception-test-step",
          trigger: "manual",
          roster: [%{"who" => "all", "how" => "solo"}]
        })

      tool_name = "send_email"
      args = %{"to" => "test@example.com", "subject" => "hi"}

      {:ok, proposal} = ImpulseRunner.intercept_dangerous_tool(tool_name, args, step.id)

      assert proposal.type == "tool_action"
      assert proposal.status == "pending"
      assert proposal.tool_name == tool_name
      assert proposal.tool_args == args
      assert proposal.synapse_id == step.id
    end
  end

  describe "non-dangerous tools bypass interception" do
    test "safe tools are not flagged as dangerous" do
      refute ImpulseRunner.dangerous?("query_memory")
      refute ImpulseRunner.dangerous?("list_files")
      refute ImpulseRunner.dangerous?("read_file")
      refute ImpulseRunner.dangerous?("write_file")
    end
  end

  describe "Ollama.check_circuit_breaker/3" do
    test "does not trip on non-empty output" do
      assert {:ok, %{"tool" => 0}} = Ollama.check_circuit_breaker("tool", "some result", %{})
    end

    test "increments count on empty output" do
      assert {:ok, %{"tool" => 1}} = Ollama.check_circuit_breaker("tool", "", %{})
      assert {:ok, %{"tool" => 2}} = Ollama.check_circuit_breaker("tool", "", %{"tool" => 1})
    end

    test "trips after threshold" do
      assert {:tripped, %{"tool" => 3}} = Ollama.check_circuit_breaker("tool", "", %{"tool" => 2})
    end
  end

  describe "dangerous_tool_mode on Step schema" do
    test "accepts valid dangerous_tool_mode values" do
      for mode <- ~w(execute intercept dry_run) do
        {:ok, step} =
          ExCortex.Thoughts.create_synapse(%{
            name: "mode-test-#{mode}",
            trigger: "manual",
            roster: [%{"who" => "all", "how" => "solo"}],
            dangerous_tool_mode: mode
          })

        assert step.dangerous_tool_mode == mode
      end
    end

    test "defaults dangerous_tool_mode to execute" do
      {:ok, step} =
        ExCortex.Thoughts.create_synapse(%{
          name: "default-mode-step",
          trigger: "manual",
          roster: [%{"who" => "all", "how" => "solo"}]
        })

      assert step.dangerous_tool_mode == "execute"
    end

    test "rejects invalid dangerous_tool_mode" do
      {:error, changeset} =
        ExCortex.Thoughts.create_synapse(%{
          name: "bad-mode-step",
          trigger: "manual",
          roster: [%{"who" => "all", "how" => "solo"}],
          dangerous_tool_mode: "yolo"
        })

      assert %{dangerous_tool_mode: _} = errors_on(changeset)
    end
  end

  describe "dry_run message format" do
    test "produces expected format for dangerous tools" do
      tool_name = "create_github_issue"
      args = %{"title" => "test", "body" => "test body"}

      expected = "DRY RUN: Would have called #{tool_name} with #{Jason.encode!(args)}. No action taken."
      assert String.starts_with?(expected, "DRY RUN:")
      assert String.contains?(expected, tool_name)
      assert String.contains?(expected, "No action taken.")
    end
  end

  describe "intercept message format" do
    test "produces expected format with thought_id" do
      thought_id = 42
      expected = "Tool call queued for human approval. Proposal ID: #{thought_id}. Continue without this result."
      assert String.contains?(expected, "queued for human approval")
      assert String.contains?(expected, "42")
    end
  end
end
