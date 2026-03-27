defmodule ExCortex.Integration.TraiteeFeaturesTest do
  use ExCortex.DataCase, async: false

  alias ExCortex.Memory
  alias ExCortex.Memory.ConversationSummarizer
  alias ExCortex.Muse.ContextBudget
  alias ExCortex.Ruminations.Middleware
  alias ExCortex.Ruminations.Middleware.Context
  alias ExCortex.Ruminations.Middleware.OutputGuard
  alias ExCortex.Ruminations.Middleware.ThreatGate
  alias ExCortex.Security.ThreatTracker

  describe "context budgeting" do
    test "budget allocates correctly for known model" do
      budget = ContextBudget.allocate("devstral-small-2:24b")
      assert budget.total == 32_768
      assert budget.context > 0
    end

    test "budget allocates correctly for unknown model with default" do
      budget = ContextBudget.allocate("unknown-model-7b")
      assert budget.total == 32_768
    end
  end

  describe "security middleware chain" do
    test "full chain runs without error" do
      id = System.unique_integer([:positive])

      middleware = [
        ExCortex.Ruminations.Middleware.SystemAuthNonce,
        ExCortex.Ruminations.Middleware.CanaryTokens,
        ExCortex.Ruminations.Middleware.UntrustedContentTagger,
        OutputGuard,
        ThreatGate,
        ExCortex.Ruminations.Middleware.ToolErrorHandler
      ]

      ctx = %Context{
        input_text: "Analyze this safe input",
        metadata: %{trust_level: "trusted"},
        daydream: %{id: id}
      }

      assert {:cont, updated} = Middleware.run_before(middleware, ctx, [])
      assert updated.input_text =~ "CANARY"
      assert updated.input_text =~ "[SYS:"

      result = Middleware.run_after(middleware, updated, "Clean response", [])
      assert result == "Clean response"

      ThreatTracker.clear(id)
    end

    test "output guard redacts credentials through the chain" do
      middleware = [OutputGuard]
      ctx = %Context{input_text: "", metadata: %{}}

      result =
        Middleware.run_after(middleware, ctx, "Key: sk-proj-abcdef1234567890abcd", [])

      assert result =~ "[REDACTED:api_key]"
    end

    test "threat gate halts at threshold" do
      id = System.unique_integer([:positive])
      ThreatTracker.increment(id, 10.0)

      ctx = %Context{
        input_text: "test",
        metadata: %{},
        daydream: %{id: id}
      }

      assert {:halt, :threat_threshold_exceeded} =
               ThreatGate.before_impulse(ctx, [])

      ThreatTracker.clear(id)
    end
  end

  describe "conversational memory" do
    test "should_summarize? threshold works" do
      refute ConversationSummarizer.should_summarize?([1, 2])
      assert ConversationSummarizer.should_summarize?([1, 2, 3])
    end
  end

  describe "engram schema accepts conversational category" do
    test "creates engram with conversational category" do
      {:ok, engram} =
        Memory.create_engram(%{
          title: "Test conversation",
          category: "conversational",
          source: "muse",
          importance: 3
        })

      assert engram.category == "conversational"
    end
  end

  describe "MMR" do
    test "memory query with legacy strategy works" do
      {:ok, _} =
        Memory.create_engram(%{
          title: "Integration test engram",
          impression: "Testing legacy query path",
          category: "semantic",
          importance: 3
        })

      results = Memory.query("integration test", strategy: :legacy, tier: :L0)
      assert is_list(results)
      assert length(results) > 0
    end

    test "memory query with mmr strategy falls back gracefully" do
      {:ok, _} =
        Memory.create_engram(%{
          title: "MMR fallback test",
          impression: "Should fall back to legacy without embeddings",
          category: "semantic",
          importance: 3
        })

      results = Memory.query("MMR fallback", strategy: :mmr, tier: :L0)
      assert is_list(results)
    end
  end
end
