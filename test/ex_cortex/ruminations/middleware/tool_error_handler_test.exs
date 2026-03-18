defmodule ExCortex.Ruminations.Middleware.ToolErrorHandlerTest do
  use ExUnit.Case, async: true

  alias ExCortex.Ruminations.Middleware.Context
  alias ExCortex.Ruminations.Middleware.ToolErrorHandler

  describe "before_impulse/2" do
    test "passes through context unchanged" do
      ctx = %Context{synapse: :test, metadata: %{foo: "bar"}}
      assert {:cont, ^ctx} = ToolErrorHandler.before_impulse(ctx, [])
    end
  end

  describe "after_impulse/3" do
    test "passes through result unchanged" do
      ctx = %Context{synapse: :test}
      result = {:ok, "some result"}
      assert ^result = ToolErrorHandler.after_impulse(ctx, result, [])
    end
  end

  describe "wrap_tool_call/3" do
    test "successful tool call passes through unchanged" do
      result = ToolErrorHandler.wrap_tool_call("my_tool", %{}, fn -> {:ok, "success"} end)
      assert result == {:ok, "success"}
    end

    test "catches exceptions and returns structured error map" do
      result =
        ToolErrorHandler.wrap_tool_call("failing_tool", %{}, fn ->
          raise "something went wrong"
        end)

      assert {:error, error_map} = result
      assert error_map.error == "something went wrong"
      assert error_map.error_type == "RuntimeError"
      assert error_map.status == "error"
      assert error_map.tool == "failing_tool"
    end

    test "catches non-RuntimeError exceptions" do
      result =
        ToolErrorHandler.wrap_tool_call("bad_tool", %{}, fn ->
          raise ArgumentError, "bad argument"
        end)

      assert {:error, error_map} = result
      assert error_map.error == "bad argument"
      assert error_map.error_type == "ArgumentError"
      assert error_map.status == "error"
      assert error_map.tool == "bad_tool"
    end

    test "catches thrown values" do
      result =
        ToolErrorHandler.wrap_tool_call("throw_tool", %{}, fn ->
          throw(:oops)
        end)

      assert {:error, error_map} = result
      assert error_map.error_type == "throw"
      assert error_map.status == "error"
      assert error_map.tool == "throw_tool"
    end

    test "catches exits" do
      result =
        ToolErrorHandler.wrap_tool_call("exit_tool", %{}, fn ->
          exit(:shutdown)
        end)

      assert {:error, error_map} = result
      assert error_map.error_type == "exit"
      assert error_map.status == "error"
      assert error_map.tool == "exit_tool"
    end
  end
end
