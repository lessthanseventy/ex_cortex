defmodule ExCortex.Evaluator do
  @moduledoc false

  alias ExCortex.Core.LLM.Ollama
  alias ExCortex.Core.Orchestrator
  alias ExCortex.DynamicActions.Template

  require Logger

  @pathways %{
    "Content Moderation" => ExCortex.Pathways.ContentModeration,
    "Code Review" => ExCortex.Pathways.CodeReview,
    "Risk Assessment" => ExCortex.Pathways.RiskAssessment,
    "Accessibility Review" => ExCortex.Pathways.AccessibilityReview,
    "Performance Audit" => ExCortex.Pathways.PerformanceAudit,
    "Incident Triage" => ExCortex.Pathways.IncidentTriage,
    "Contract Review" => ExCortex.Pathways.ContractReview,
    "Dependency Audit" => ExCortex.Pathways.DependencyAudit,
    "Dev Team" => ExCortex.Pathways.DevTeam
  }

  def pathways, do: @pathways

  def current_cluster do
    case :persistent_term.get(:evaluator_current_cluster, :not_cached) do
      :not_cached ->
        result = do_find_cluster()
        :persistent_term.put(:evaluator_current_cluster, result)
        result

      cached ->
        cached
    end
  end

  def invalidate_cluster_cache do
    :persistent_term.put(:evaluator_current_cluster, :not_cached)
  end

  defp do_find_cluster do
    import Ecto.Query

    alias ExCortex.Neurons.Neuron

    names =
      ExCortex.Repo.all(from(r in Neuron, where: r.type == "role", select: r.name))

    Enum.find_value(@pathways, fn {cluster_name, mod} ->
      meta = mod.metadata()
      role_names = Enum.map(meta.roles, & &1.name)

      if Enum.all?(role_names, &(&1 in names)) do
        {cluster_name, mod}
      end
    end)
  end

  def evaluate(input_text, opts \\ []) do
    case current_cluster() do
      nil ->
        {:error, :no_cluster_installed}

      {_name, pathway_mod} ->
        meta = pathway_mod.metadata()

        ollama_url =
          Application.get_env(:ex_cortex, :ollama_url, "http://127.0.0.1:11434")

        ollama_api_key = Application.get_env(:ex_cortex, :ollama_api_key)

        provider = Keyword.get(opts, :provider, Ollama.new(base_url: ollama_url, api_key: ollama_api_key))

        roles = build_roles_from_pathway(meta)
        actions_mod = build_actions_from_pathway(meta)

        case Orchestrator.evaluate(
               %{subject: input_text},
               %{},
               roles: roles,
               actions: actions_mod,
               strategy: meta.strategy,
               llm_provider: provider,
               guards: []
             ) do
          {:approve, details} ->
            Phoenix.PubSub.broadcast(ExCortex.PubSub, "evaluation:results", :refresh)
            {:approve, details}

          other ->
            other
        end
    end
  end

  defp build_roles_from_pathway(meta) do
    role_names = Enum.map(meta.roles, fn role_def ->
      safe_name = role_def.name |> String.replace(~r/[^a-zA-Z0-9]/, "") |> Macro.camelize()
      Module.concat([ExCortex, Roles, safe_name])
    end)

    # Check if all modules already exist — fast path, no lock needed
    unless Enum.all?(role_names, &Code.ensure_loaded?/1) do
      ensure_roles_built(meta, role_names)
    end

    role_names
  end

  # Serialize module creation through a single caller. The first process to
  # register wins and builds; all others block until it's done.
  defp ensure_roles_built(meta, role_names) do
    case :global.register_name(:evaluator_role_builder, self()) do
      :yes ->
        # We won — build all modules
        Enum.zip(meta.roles, role_names)
        |> Enum.each(fn {role_def, mod_name} ->
          unless Code.ensure_loaded?(mod_name) do
            create_role_module(mod_name, role_def)
          end
        end)

        :global.unregister_name(:evaluator_role_builder)

      :no ->
        # Another process is building — wait for it to finish
        Process.sleep(100)

        unless Enum.all?(role_names, &Code.ensure_loaded?/1) do
          # Still not done, try again (will either build or wait)
          ensure_roles_built(meta, role_names)
        end
    end
  end

  defp create_role_module(mod_name, role_def) do
    contents =
      quote do
        use ExCortex.Core.Role

        system_prompt(unquote(role_def.system_prompt))

        unquote_splicing(
          Enum.map(role_def.perspectives, fn p ->
            quote do
              perspective(unquote(String.to_atom(p.name)),
                model: unquote(p.model),
                strategy: unquote(String.to_atom(p.strategy)),
                name: unquote("#{role_def.name}.#{p.name}")
              )
            end
          end)
        )

        def build_prompt(input, _context) do
          "Evaluate the following:\n\n#{inspect(input)}"
        end
      end

    try do
      Module.create(mod_name, contents, Macro.Env.location(__ENV__))
    rescue
      _ ->
        unless Code.ensure_loaded?(mod_name) do
          Logger.warning("Failed to create role module #{inspect(mod_name)} — skipping")
        end
    end
  end

  defp build_actions_from_pathway(meta) do
    mod_name = Module.concat([ExCortex, DynamicActions, :Template])

    if !Code.ensure_loaded?(mod_name) do
      action_defs =
        Enum.map(meta.actions, fn action ->
          quote do
            action(unquote(action))
          end
        end)

      contents =
        quote do
          use ExCortex.Core.Actions

          unquote_splicing(action_defs)
        end

      try do
        Module.create(mod_name, contents, Macro.Env.location(__ENV__))
      rescue
        _error in [Code.LoadError] ->
          Logger.error("Failed to load dependencies for actions module #{inspect(mod_name)}",
            context: %{actions: meta.actions, error_type: "LoadError"}
          )

          Template

        _error in [CompileError] ->
          Logger.error("Failed to compile actions module #{inspect(mod_name)}",
            context: %{actions: meta.actions, error_type: "CompileError"}
          )

          Template

        error ->
          Logger.error("Failed to create dynamic actions module #{inspect(mod_name)}: #{inspect(error)}",
            context: %{actions: meta.actions, error_type: Exception.message(error)}
          )

          Template
      end
    end

    mod_name
  end

end
