defmodule ExCortex.Ruminations.Middleware do
  @moduledoc false

  defmodule Context do
    @moduledoc false
    defstruct [:synapse, :daydream, :input_text, :neurons, metadata: %{}]

    @type t :: %__MODULE__{
            synapse: term(),
            daydream: term(),
            input_text: String.t() | nil,
            neurons: [term()] | nil,
            metadata: map()
          }
  end

  @callback before_impulse(context :: Context.t(), opts :: keyword()) ::
              {:cont, Context.t()} | {:halt, reason :: term()}

  @callback after_impulse(context :: Context.t(), result :: term(), opts :: keyword()) ::
              term()

  @callback wrap_tool_call(tool_name :: String.t(), tool_args :: map(), execute_fn :: (-> term())) ::
              term()

  @doc """
  Runs `before_impulse` through the middleware chain.
  Each entry can be a module or a `{module, opts}` tuple.
  Short-circuits on `{:halt, reason}`.
  """
  def run_before(middlewares, ctx, default_opts) do
    Enum.reduce_while(middlewares, {:cont, ctx}, fn middleware, {:cont, acc_ctx} ->
      {mod, opts} = normalize(middleware, default_opts)

      case mod.before_impulse(acc_ctx, opts) do
        {:cont, new_ctx} -> {:cont, {:cont, new_ctx}}
        {:halt, reason} -> {:halt, {:halt, reason}}
      end
    end)
  end

  @doc """
  Runs `after_impulse` through the middleware chain, threading the result.
  """
  def run_after(middlewares, ctx, result, default_opts) do
    Enum.reduce(middlewares, result, fn middleware, acc_result ->
      {mod, opts} = normalize(middleware, default_opts)
      mod.after_impulse(ctx, acc_result, opts)
    end)
  end

  @doc """
  Nests `wrap_tool_call` callbacks so the first middleware is outermost.
  """
  def wrap_tool(middlewares, name, args, execute_fn) do
    wrapped =
      middlewares
      |> Enum.reverse()
      |> Enum.reduce(execute_fn, fn middleware, inner_fn ->
        {mod, _opts} = normalize(middleware, [])
        fn -> mod.wrap_tool_call(name, args, inner_fn) end
      end)

    wrapped.()
  end

  @doc """
  Resolves a list of string module names to loaded modules that implement this behaviour.
  """
  def resolve(names) do
    Enum.flat_map(names, &resolve_one/1)
  end

  defp resolve_one(name) do
    module = String.to_existing_atom(name)

    if implements_behaviour?(module) do
      [module]
    else
      []
    end
  rescue
    ArgumentError -> []
  end

  defp normalize({mod, opts}, _default_opts), do: {mod, opts}
  defp normalize(mod, default_opts), do: {mod, default_opts}

  defp implements_behaviour?(module) do
    Code.ensure_loaded?(module) &&
      function_exported?(module, :before_impulse, 2) &&
      function_exported?(module, :after_impulse, 3) &&
      function_exported?(module, :wrap_tool_call, 3)
  end
end
