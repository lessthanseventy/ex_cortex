defmodule ExCortex.Core.Orchestrator do
  @moduledoc """
  Multi-agent orchestrator. Fans out to role variants in parallel,
  collects verdicts, runs consensus, returns decision.
  """

  alias ExCortex.Core.Consensus
  alias ExCortex.Core.Registry.CodeResource
  alias ExCortex.Core.Registry.DBResource
  alias ExCortex.Core.Registry.RoleAdapter
  alias ExCortex.Core.Verdict

  require Logger

  @default_timeout 90_000

  def evaluate(input, context, opts) do
    roles = Keyword.get_lazy(opts, :roles, fn -> resolve_registry_roles() end)
    strategy = Keyword.fetch!(opts, :strategy)
    provider = Keyword.fetch!(opts, :llm_provider)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    verdicts = fan_out(roles, input, context, provider, timeout)

    {active_verdicts, _shadow_verdicts} =
      Enum.split_with(verdicts, fn v -> :shadow not in v.flags end)

    role_results =
      active_verdicts
      |> Enum.group_by(& &1.role)
      |> Enum.map(fn {_role, vs} -> Consensus.role_consensus(vs) end)

    {action, confidence} = Consensus.cross_role_decision(role_results, strategy)

    base = %{
      verdicts: verdicts,
      role_results: role_results,
      action: action,
      confidence: confidence
    }

    case action do
      :approve -> {:approve, base}
      _ -> {:reject, base}
    end
  end

  defp fan_out(roles, input, context, provider, timeout) do
    specs = Enum.flat_map(roles, &build_specs/1)

    tasks =
      Enum.map(specs, fn spec ->
        Task.async(fn -> run_agent(spec, input, context, provider) end)
      end)

    spec_by_ref = Map.new(Enum.zip(tasks, specs), fn {task, spec} -> {task.ref, spec} end)

    tasks
    |> Task.yield_many(timeout: timeout)
    |> Enum.map(fn {task, result} ->
      spec = spec_by_ref[task.ref]

      case result do
        {:ok, %Verdict{} = v} ->
          v

        _ ->
          Task.shutdown(task, :brutal_kill)
          timeout_verdict(spec, timeout)
      end
    end)
  end

  defp run_agent(spec, input, context, provider) do
    %{config: config} = spec
    system = get_system_prompt(spec)
    prompt = get_build_prompt(spec, input, context)

    messages = [
      %{role: "system", content: system},
      %{role: "user", content: prompt}
    ]

    start = System.monotonic_time(:millisecond)

    case ExCortex.Core.LLM.chat(provider, config.model, messages) do
      {:ok, text} ->
        latency = System.monotonic_time(:millisecond) - start
        verdict = parse_agent_response(spec, text, config)
        extra_flags = Map.get(spec, :flags, [])
        %{verdict | latency_ms: latency, flags: Enum.uniq(verdict.flags ++ extra_flags)}

      {:error, reason} ->
        latency = System.monotonic_time(:millisecond) - start

        Verdict.new(
          role: spec_role_atom(spec),
          variant: spec.variant,
          action: :abstain,
          confidence: 0.0,
          reasoning: "Error: #{inspect(reason)}",
          model: config.model,
          strategy: config.strategy,
          latency_ms: latency
        )
    end
  end

  defp resolve_registry_roles do
    if Process.whereis(ExCortex.Core.Registry) do
      ExCortex.Core.Registry.list(:role, status: :active) ++
        ExCortex.Core.Registry.list(:role, status: :shadow)
    else
      []
    end
  end

  defp build_specs(role) when is_atom(role) do
    for variant <- role.perspectives() do
      config = role.variant_config(variant)
      %{module: role, variant: variant, config: config, source: :code}
    end
  end

  defp build_specs(%CodeResource{module: module}), do: build_specs(module)

  defp build_specs(%DBResource{config: db_config, name: name, status: status}) do
    flags = if status == :shadow, do: [:shadow], else: []

    for variant <- RoleAdapter.perspectives(db_config) do
      config = RoleAdapter.variant_config(db_config, variant)
      config = %{config | name: "#{name}.#{variant}"}
      %{db_config: db_config, name: name, variant: variant, config: config, source: :db, flags: flags}
    end
  end

  defp get_system_prompt(%{module: role, variant: variant}), do: role.system_prompt(variant)
  defp get_system_prompt(%{db_config: config}), do: RoleAdapter.system_prompt(config)

  defp get_build_prompt(%{module: role}, input, context), do: role.build_prompt(input, context)
  defp get_build_prompt(%{db_config: config}, input, _context), do: RoleAdapter.build_prompt(config, input)

  defp parse_agent_response(%{module: role}, text, config) do
    role.parse_response(text, config.name, model: config.model, strategy: config.strategy)
  end

  defp parse_agent_response(%{db_config: db_config}, text, config) do
    RoleAdapter.parse_response(db_config, text, config.name, model: config.model, strategy: config.strategy)
  end

  defp timeout_verdict(spec, timeout) do
    Verdict.new(
      role: spec_role_atom(spec),
      variant: spec.variant,
      action: :abstain,
      confidence: 0.0,
      reasoning: "Agent timed out after #{timeout}ms",
      model: spec.config.model,
      strategy: :timeout
    )
  end

  defp spec_role_atom(%{module: module}) do
    module |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()
  end

  defp spec_role_atom(%{name: name}), do: String.to_atom(name)
end
