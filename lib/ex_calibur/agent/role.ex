defmodule ExCalibur.Agent.Role do
  @moduledoc """
  Behaviour and macro for defining agent roles.

  ## Example

      defmodule MyApp.SecurityReviewer do
        use ExCalibur.Agent.Role

        perspective :alpha, model: "gemma3:4b", strategy: :cod, name: "security.alpha"
        system_prompt "You are a security reviewer."

        @impl true
        def build_prompt(input, _context) do
          "Review for issues: \#{inspect(input)}"
        end
      end
  """

  @callback perspectives() :: [atom()]
  @callback variant_config(variant :: atom()) :: map()
  @callback system_prompt(variant :: atom()) :: String.t()
  @callback build_prompt(input :: map(), context :: map()) :: String.t()
  @callback parse_response(text :: String.t(), agent_name :: String.t(), opts :: keyword()) ::
              ExCalibur.Agent.Verdict.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour ExCalibur.Agent.Role

      import ExCalibur.Agent.Role, only: [perspective: 2, system_prompt: 1]

      Module.register_attribute(__MODULE__, :agent_perspectives, accumulate: true)
      Module.register_attribute(__MODULE__, :agent_system_prompt, [])
      @before_compile ExCalibur.Agent.Role
    end
  end

  defmacro perspective(name, opts) do
    quote do
      @agent_perspectives {unquote(name), unquote(opts)}
    end
  end

  defmacro system_prompt(text) do
    quote do
      @agent_system_prompt unquote(text)
    end
  end

  defmacro __before_compile__(env) do
    perspectives = env.module |> Module.get_attribute(:agent_perspectives) |> Enum.reverse()
    base_prompt = Module.get_attribute(env.module, :agent_system_prompt) || ""
    perspective_names = Enum.map(perspectives, fn {name, _} -> name end)

    variant_config_fns =
      for {name, opts} <- perspectives do
        model = Keyword.fetch!(opts, :model)
        strategy = Keyword.fetch!(opts, :strategy)
        agent_name = Keyword.get(opts, :name, "#{env.module}.#{name}")

        quote do
          def variant_config(unquote(name)) do
            %{
              model: unquote(model),
              strategy: unquote(strategy),
              name: unquote(agent_name),
              variant: unquote(name)
            }
          end
        end
      end

    quote do
      def perspectives, do: unquote(perspective_names)

      unquote_splicing(variant_config_fns)

      def system_prompt(_variant), do: unquote(base_prompt)

      def parse_response(text, agent_name) do
        ExCalibur.Agent.Role.DefaultParser.parse(text, agent_name, __MODULE__, [])
      end

      def parse_response(text, agent_name, opts) do
        ExCalibur.Agent.Role.DefaultParser.parse(text, agent_name, __MODULE__, opts)
      end

      defoverridable system_prompt: 1, parse_response: 2, parse_response: 3
    end
  end
end
