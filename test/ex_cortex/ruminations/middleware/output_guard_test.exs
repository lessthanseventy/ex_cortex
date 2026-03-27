defmodule ExCortex.Ruminations.Middleware.OutputGuardTest do
  use ExUnit.Case, async: true

  alias ExCortex.Ruminations.Middleware.Context
  alias ExCortex.Ruminations.Middleware.OutputGuard

  describe "after_impulse/3" do
    test "redacts API keys" do
      ctx = %Context{input_text: "", metadata: %{}}
      result = "Use this key: sk-proj-abc123def456ghi789jkl"
      cleaned = OutputGuard.after_impulse(ctx, result, [])
      assert cleaned =~ "[REDACTED:api_key]"
      refute cleaned =~ "sk-proj-abc123"
    end

    test "redacts AWS access keys" do
      ctx = %Context{input_text: "", metadata: %{}}
      result = "AWS key: AKIAIOSFODNN7EXAMPLE"
      cleaned = OutputGuard.after_impulse(ctx, result, [])
      assert cleaned =~ "[REDACTED:aws_key]"
    end

    test "redacts bearer tokens" do
      ctx = %Context{input_text: "", metadata: %{}}
      result = "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc"
      cleaned = OutputGuard.after_impulse(ctx, result, [])
      assert cleaned =~ "[REDACTED:bearer_token]"
    end

    test "passes through clean output" do
      ctx = %Context{input_text: "", metadata: %{}}
      result = "The deployment completed successfully"
      assert OutputGuard.after_impulse(ctx, result, []) == result
    end

    test "handles non-string results" do
      ctx = %Context{input_text: "", metadata: %{}}
      assert OutputGuard.after_impulse(ctx, {:ok, "data"}, []) == {:ok, "data"}
    end
  end

  describe "wrap_tool_call/3" do
    test "scans tool arguments for shell injection" do
      result =
        OutputGuard.wrap_tool_call("run_sandbox", %{"command" => "mix test; rm -rf /"}, fn ->
          {:ok, "ran"}
        end)

      assert {:error, %{error: error}} = result
      assert error =~ "blocked"
    end

    test "allows clean tool arguments" do
      result =
        OutputGuard.wrap_tool_call("run_sandbox", %{"command" => "mix test"}, fn ->
          {:ok, "passed"}
        end)

      assert {:ok, "passed"} = result
    end
  end
end
