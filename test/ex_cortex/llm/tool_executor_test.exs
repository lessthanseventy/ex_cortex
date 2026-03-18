defmodule ExCortex.LLM.ToolExecutorTest do
  use ExUnit.Case, async: true

  alias ExCortex.LLM.ToolExecutor

  # A minimal tool struct that quacks like a ReqLLM.Tool
  defmodule FakeTool do
    @moduledoc false
    defstruct [:name, :function]
  end

  # A test middleware that uppercases tool output
  defmodule UpcaseMiddleware do
    @moduledoc false
    @behaviour ExCortex.Ruminations.Middleware

    @impl true
    def before_impulse(ctx, _opts), do: {:cont, ctx}

    @impl true
    def after_impulse(_ctx, result, _opts), do: result

    @impl true
    def wrap_tool_call(_name, _args, execute_fn) do
      case execute_fn.() do
        {:ok, val} -> {:ok, String.upcase(to_string(val))}
        other -> other
      end
    end
  end

  describe "execute/5 — safe execution" do
    test "executes a known tool and returns output, log entry, and breaker state" do
      tool = %FakeTool{name: "read_file", function: fn _args -> {:ok, "file contents"} end}

      {output, log, breaker} = ToolExecutor.execute("read_file", %{"path" => "foo.ex"}, [tool], %{})

      assert output == "file contents"
      assert log == %{tool: "read_file", input: %{"path" => "foo.ex"}, output: "file contents"}
      assert breaker == %{"read_file" => 0}
    end

    test "returns error string when tool execution fails" do
      tool = %FakeTool{name: "read_file", function: fn _args -> {:error, "not found"} end}

      {output, log, _breaker} = ToolExecutor.execute("read_file", %{}, [tool], %{})

      assert output =~ "Error:"
      assert log.output =~ "Error:"
    end

    test "returns error when tool is not found" do
      {output, log, _breaker} = ToolExecutor.execute("unknown_tool", %{}, [], %{})

      assert output =~ "not found"
      assert log.tool == "unknown_tool"
    end
  end

  describe "execute/5 — circuit breaker" do
    test "skips tool when breaker count >= 3" do
      breaker = %{"read_file" => 3}
      tool = %FakeTool{name: "read_file", function: fn _args -> {:ok, "data"} end}

      {output, log, new_breaker} = ToolExecutor.execute("read_file", %{}, [tool], breaker)

      assert output =~ "Skipping"
      assert output =~ "read_file"
      assert log.output =~ "Skipping"
      # breaker state unchanged
      assert new_breaker == breaker
    end

    test "increments breaker count on empty result" do
      tool = %FakeTool{name: "search", function: fn _args -> {:ok, ""} end}

      {_output, _log, breaker} = ToolExecutor.execute("search", %{}, [tool], %{})

      assert breaker["search"] == 1
    end

    test "increments breaker count on empty list result" do
      tool = %FakeTool{name: "search", function: fn _args -> {:ok, "[]"} end}

      {_output, _log, breaker} = ToolExecutor.execute("search", %{}, [tool], %{})

      assert breaker["search"] == 1
    end

    test "resets breaker count on non-empty result" do
      tool = %FakeTool{name: "search", function: fn _args -> {:ok, "found stuff"} end}

      {_output, _log, breaker} = ToolExecutor.execute("search", %{}, [tool], %{"search" => 2})

      assert breaker["search"] == 0
    end

    test "increments on 'is not available' result" do
      tool = %FakeTool{name: "bad_tool", function: fn _args -> {:ok, "Tool bad_tool is not available in this step"} end}

      {_output, _log, breaker} = ToolExecutor.execute("bad_tool", %{}, [tool], %{})

      assert breaker["bad_tool"] == 1
    end
  end

  describe "execute/5 — dangerous tool handling" do
    test "dry_run mode returns dry run message for dangerous tools" do
      tool = %FakeTool{name: "send_email", function: fn _args -> {:ok, "sent"} end}

      {output, log, _breaker} =
        ToolExecutor.execute("send_email", %{"to" => "a@b.com"}, [tool], %{}, dangerous_tool_mode: "dry_run")

      assert output =~ "DRY RUN"
      assert output =~ "send_email"
      assert log.output =~ "DRY RUN"
    end

    test "execute mode runs dangerous tools normally" do
      tool = %FakeTool{name: "send_email", function: fn _args -> {:ok, "sent ok"} end}

      {output, _log, _breaker} =
        ToolExecutor.execute("send_email", %{"to" => "a@b.com"}, [tool], %{}, dangerous_tool_mode: "execute")

      assert output == "sent ok"
    end

    test "non-dangerous tools run normally regardless of mode" do
      tool = %FakeTool{name: "read_file", function: fn _args -> {:ok, "contents"} end}

      {output, _log, _breaker} =
        ToolExecutor.execute("read_file", %{}, [tool], %{}, dangerous_tool_mode: "dry_run")

      assert output == "contents"
    end
  end

  describe "execute/5 — middleware" do
    test "applies middleware to tool execution" do
      tool = %FakeTool{name: "read_file", function: fn _args -> {:ok, "hello"} end}

      {output, log, _breaker} =
        ToolExecutor.execute("read_file", %{}, [tool], %{}, middleware: [UpcaseMiddleware])

      assert output == "HELLO"
      assert log.output == "HELLO"
    end
  end

  describe "empty_result?/1" do
    test "empty string is empty" do
      assert ToolExecutor.empty_result?("")
      assert ToolExecutor.empty_result?("  ")
    end

    test "empty list string is empty" do
      assert ToolExecutor.empty_result?("[]")
      assert ToolExecutor.empty_result?("[]\n")
    end

    test "unavailable message is empty" do
      assert ToolExecutor.empty_result?("Tool foo is not available in this step")
    end

    test "real content is not empty" do
      refute ToolExecutor.empty_result?("some data")
    end

    test "non-binary is empty" do
      assert ToolExecutor.empty_result?(nil)
    end
  end
end
