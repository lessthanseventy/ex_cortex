defmodule ExCortex.Ruminations.Middleware.CanaryTokensTest do
  use ExUnit.Case, async: true

  alias ExCortex.Ruminations.Middleware.CanaryTokens
  alias ExCortex.Ruminations.Middleware.Context

  describe "before_impulse/2" do
    test "injects canary token into input_text" do
      ctx = %Context{input_text: "Evaluate this code", metadata: %{}}
      {:cont, updated} = CanaryTokens.before_impulse(ctx, [])

      assert updated.input_text =~ "<!-- CANARY:"
      assert updated.metadata[:canary_token]
    end

    test "generates unique tokens each time" do
      ctx = %Context{input_text: "test", metadata: %{}}
      {:cont, ctx1} = CanaryTokens.before_impulse(ctx, [])
      {:cont, ctx2} = CanaryTokens.before_impulse(ctx, [])
      assert ctx1.metadata[:canary_token] != ctx2.metadata[:canary_token]
    end
  end

  describe "after_impulse/3" do
    test "detects leaked canary and strips it" do
      token = "abc123def456"
      ctx = %Context{input_text: "test", metadata: %{canary_token: token}}
      result = "Here is the answer <!-- CANARY:abc123def456 --> and more text"

      cleaned = CanaryTokens.after_impulse(ctx, result, [])
      refute cleaned =~ "CANARY"
      assert cleaned =~ "Here is the answer"
    end

    test "passes through clean output unchanged" do
      ctx = %Context{input_text: "test", metadata: %{canary_token: "abc123"}}
      result = "Clean output with no leaks"
      assert CanaryTokens.after_impulse(ctx, result, []) == result
    end

    test "handles non-string results" do
      ctx = %Context{input_text: "test", metadata: %{canary_token: "abc123"}}
      assert CanaryTokens.after_impulse(ctx, {:ok, "data"}, []) == {:ok, "data"}
    end
  end

  describe "wrap_tool_call/3" do
    test "passes through" do
      assert CanaryTokens.wrap_tool_call("tool", %{}, fn -> :ok end) == :ok
    end
  end
end
