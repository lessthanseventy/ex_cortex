defmodule ExCortex.Core.Actions do
  @moduledoc """
  DSL for declaring the decision space and action conflict topology.

  ## Example

      defmodule MyApp.Actions do
        use ExCortex.Core.Actions

        action :approve, conflicts_with: [:reject]
        action :reject, conflicts_with: [:approve]
        action :escalate, orthogonal: true
      end
  """

  defmacro __using__(_opts) do
    quote do
      import ExCortex.Core.Actions, only: [action: 1, action: 2]

      Module.register_attribute(__MODULE__, :agent_actions, accumulate: true)
      @before_compile ExCortex.Core.Actions
    end
  end

  defmacro action(name, opts \\ []) do
    quote do
      @agent_actions {unquote(name), unquote(opts)}
    end
  end

  defmacro __before_compile__(env) do
    actions = Module.get_attribute(env.module, :agent_actions)

    conflicts_map =
      for {name, opts} <- actions, into: %{} do
        {name, Keyword.get(opts, :conflicts_with, [])}
      end

    orthogonal_set =
      for {name, opts} <- actions, Keyword.get(opts, :orthogonal, false), into: MapSet.new() do
        name
      end

    action_names = Enum.map(actions, fn {name, _} -> name end)

    quote do
      def actions, do: unquote(action_names)

      def conflicts?(a, b) do
        conflicts_map = unquote(Macro.escape(conflicts_map))
        orthogonal = unquote(Macro.escape(orthogonal_set))
        not_orthogonal = not MapSet.member?(orthogonal, a) and not MapSet.member?(orthogonal, b)
        not_orthogonal and (b in Map.get(conflicts_map, a, []) or a in Map.get(conflicts_map, b, []))
      end

      def orthogonal?(action) do
        MapSet.member?(unquote(Macro.escape(orthogonal_set)), action)
      end
    end
  end
end
