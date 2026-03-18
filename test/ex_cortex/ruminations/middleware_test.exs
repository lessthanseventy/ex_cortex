defmodule ExCortex.Ruminations.MiddlewareTest do
  use ExUnit.Case, async: true

  alias ExCortex.Ruminations.Middleware
  alias ExCortex.Ruminations.Middleware.Context

  defmodule PassthroughMiddleware do
    @moduledoc false
    @behaviour Middleware

    @impl true
    def before_impulse(ctx, _opts), do: {:cont, ctx}

    @impl true
    def after_impulse(_ctx, result, _opts), do: result

    @impl true
    def wrap_tool_call(_name, _args, execute_fn), do: execute_fn.()
  end

  defmodule HaltMiddleware do
    @moduledoc false
    @behaviour Middleware

    @impl true
    def before_impulse(_ctx, _opts), do: {:halt, :stopped}

    @impl true
    def after_impulse(_ctx, result, _opts), do: result

    @impl true
    def wrap_tool_call(_name, _args, execute_fn), do: execute_fn.()
  end

  defmodule MetadataMiddleware do
    @moduledoc false
    @behaviour Middleware

    @impl true
    def before_impulse(ctx, opts) do
      key = Keyword.get(opts, :key, :touched)
      {:cont, %{ctx | metadata: Map.put(ctx.metadata, key, true)}}
    end

    @impl true
    def after_impulse(_ctx, result, _opts), do: result

    @impl true
    def wrap_tool_call(_name, _args, execute_fn), do: execute_fn.()
  end

  defmodule UppercaseResultMiddleware do
    @moduledoc false
    @behaviour Middleware

    @impl true
    def before_impulse(ctx, _opts), do: {:cont, ctx}

    @impl true
    def after_impulse(_ctx, result, _opts) when is_binary(result), do: String.upcase(result)
    def after_impulse(_ctx, result, _opts), do: result

    @impl true
    def wrap_tool_call(_name, _args, execute_fn), do: execute_fn.()
  end

  defmodule SuffixResultMiddleware do
    @moduledoc false
    @behaviour Middleware

    @impl true
    def before_impulse(ctx, _opts), do: {:cont, ctx}

    @impl true
    def after_impulse(_ctx, result, _opts) when is_binary(result), do: result <> "_suffix"
    def after_impulse(_ctx, result, _opts), do: result

    @impl true
    def wrap_tool_call(_name, _args, execute_fn), do: execute_fn.()
  end

  defmodule LoggingToolMiddleware do
    @moduledoc false
    @behaviour Middleware

    @impl true
    def before_impulse(ctx, _opts), do: {:cont, ctx}

    @impl true
    def after_impulse(_ctx, result, _opts), do: result

    @impl true
    def wrap_tool_call(name, _args, execute_fn) do
      result = execute_fn.()
      {name, result}
    end
  end

  defmodule TaggingToolMiddleware do
    @moduledoc false
    @behaviour Middleware

    @impl true
    def before_impulse(ctx, _opts), do: {:cont, ctx}

    @impl true
    def after_impulse(_ctx, result, _opts), do: result

    @impl true
    def wrap_tool_call(_name, _args, execute_fn) do
      result = execute_fn.()
      {:tagged, result}
    end
  end

  describe "Context struct" do
    test "has expected fields with defaults" do
      ctx = %Context{}
      assert ctx.synapse == nil
      assert ctx.daydream == nil
      assert ctx.input_text == nil
      assert ctx.neurons == nil
      assert ctx.metadata == %{}
    end

    test "accepts all fields" do
      ctx = %Context{
        synapse: :syn,
        daydream: :day,
        input_text: "hello",
        neurons: [:a],
        metadata: %{foo: :bar}
      }

      assert ctx.synapse == :syn
      assert ctx.metadata == %{foo: :bar}
    end
  end

  describe "run_before/3" do
    test "returns {:cont, ctx} when no middleware" do
      ctx = %Context{input_text: "hi"}
      assert {:cont, ^ctx} = Middleware.run_before([], ctx, [])
    end

    test "passes context through a single passthrough middleware" do
      ctx = %Context{input_text: "hi"}
      assert {:cont, ^ctx} = Middleware.run_before([PassthroughMiddleware], ctx, [])
    end

    test "halts on first halting middleware" do
      ctx = %Context{input_text: "hi"}

      assert {:halt, :stopped} =
               Middleware.run_before([HaltMiddleware, MetadataMiddleware], ctx, [])
    end

    test "modifies context through chain" do
      ctx = %Context{metadata: %{}}

      assert {:cont, result_ctx} =
               Middleware.run_before([MetadataMiddleware], ctx, key: :step1)

      assert result_ctx.metadata == %{step1: true}
    end

    test "chains multiple middleware in order" do
      ctx = %Context{metadata: %{}}

      middlewares = [
        {MetadataMiddleware, key: :first},
        {MetadataMiddleware, key: :second}
      ]

      assert {:cont, result_ctx} = Middleware.run_before(middlewares, ctx, [])
      assert result_ctx.metadata == %{first: true, second: true}
    end

    test "halt stops further processing" do
      ctx = %Context{metadata: %{}}

      middlewares = [
        {MetadataMiddleware, key: :before_halt},
        HaltMiddleware,
        {MetadataMiddleware, key: :after_halt}
      ]

      assert {:halt, :stopped} = Middleware.run_before(middlewares, ctx, [])
    end
  end

  describe "run_after/4" do
    test "returns result when no middleware" do
      ctx = %Context{}
      assert Middleware.run_after([], ctx, "hello", []) == "hello"
    end

    test "threads result through chain" do
      ctx = %Context{}

      assert Middleware.run_after(
               [UppercaseResultMiddleware, SuffixResultMiddleware],
               ctx,
               "hello",
               []
             ) == "HELLO_suffix"
    end

    test "single middleware transforms result" do
      ctx = %Context{}
      assert Middleware.run_after([UppercaseResultMiddleware], ctx, "hello", []) == "HELLO"
    end
  end

  describe "wrap_tool/4" do
    test "executes function when no middleware" do
      assert Middleware.wrap_tool([], "tool", %{}, fn -> :result end) == :result
    end

    test "single middleware wraps tool call" do
      assert Middleware.wrap_tool([LoggingToolMiddleware], "my_tool", %{}, fn -> :ok end) ==
               {"my_tool", :ok}
    end

    test "nests multiple middleware wrappers" do
      middlewares = [TaggingToolMiddleware, LoggingToolMiddleware]

      result = Middleware.wrap_tool(middlewares, "tool", %{}, fn -> :data end)
      # TaggingToolMiddleware wraps outermost, LoggingToolMiddleware wraps inner
      # Execution: TaggingToolMiddleware calls execute_fn which is LoggingToolMiddleware's wrap
      # LoggingToolMiddleware returns {"tool", :data}
      # TaggingToolMiddleware returns {:tagged, {"tool", :data}}
      assert result == {:tagged, {"tool", :data}}
    end
  end

  describe "resolve/1" do
    test "returns empty list for empty input" do
      assert Middleware.resolve([]) == []
    end

    test "resolves valid module names" do
      modules =
        Middleware.resolve([
          "Elixir.ExCortex.Ruminations.MiddlewareTest.PassthroughMiddleware"
        ])

      assert modules == [PassthroughMiddleware]
    end

    test "filters out non-existent modules" do
      modules =
        Middleware.resolve([
          "Elixir.ExCortex.Ruminations.MiddlewareTest.PassthroughMiddleware",
          "Elixir.ExCortex.Ruminations.NonExistentMiddleware"
        ])

      assert modules == [PassthroughMiddleware]
    end

    test "filters out modules that don't implement the behaviour" do
      modules = Middleware.resolve(["Elixir.Enum"])
      assert modules == []
    end
  end
end
