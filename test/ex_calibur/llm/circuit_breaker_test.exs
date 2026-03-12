defmodule ExCalibur.LLM.CircuitBreakerTest do
  use ExUnit.Case, async: true

  alias ExCalibur.LLM.Ollama

  describe "empty_result?/1" do
    test "detects empty string" do
      assert Ollama.empty_result?("")
    end

    test "detects whitespace-only string" do
      assert Ollama.empty_result?("   \n  ")
    end

    test "detects empty list string" do
      assert Ollama.empty_result?("[]")
    end

    test "detects empty list string with newline" do
      assert Ollama.empty_result?("[]\n")
    end

    test "detects error string" do
      assert Ollama.empty_result?("Error: something failed")
    end

    test "rejects non-empty content" do
      refute Ollama.empty_result?("some real content here")
    end

    test "detects nil" do
      assert Ollama.empty_result?(nil)
    end
  end

  describe "check_circuit_breaker/3" do
    test "returns ok for first empty result" do
      assert {:ok, %{"my_tool" => 1}} = Ollama.check_circuit_breaker("my_tool", "", %{})
    end

    test "returns ok for second empty result" do
      assert {:ok, %{"my_tool" => 2}} =
               Ollama.check_circuit_breaker("my_tool", "", %{"my_tool" => 1})
    end

    test "returns tripped on third empty result" do
      assert {:tripped, %{"my_tool" => 3}} =
               Ollama.check_circuit_breaker("my_tool", "", %{"my_tool" => 2})
    end

    test "resets counter on non-empty result" do
      assert {:ok, %{"my_tool" => 0}} =
               Ollama.check_circuit_breaker("my_tool", "real data", %{"my_tool" => 2})
    end

    test "tracks multiple tools independently" do
      bs = %{"tool_a" => 2, "tool_b" => 0}
      assert {:tripped, %{"tool_a" => 3}} = Ollama.check_circuit_breaker("tool_a", "", bs)
      assert {:ok, %{"tool_b" => 1}} = Ollama.check_circuit_breaker("tool_b", "", bs)
    end
  end
end
