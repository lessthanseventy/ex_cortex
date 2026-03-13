defmodule ExCalibur.Evaluator do
  @moduledoc false

  alias ExCalibur.Agent.LLM.Ollama
  alias ExCalibur.Agent.Orchestrator

  require Logger

  @charters %{
    "Content Moderation" => ExCalibur.Charters.ContentModeration,
    "Code Review" => ExCalibur.Charters.CodeReview,
    "Risk Assessment" => ExCalibur.Charters.RiskAssessment,
    "Accessibility Review" => ExCalibur.Charters.AccessibilityReview,
    "Performance Audit" => ExCalibur.Charters.PerformanceAudit,
    "Incident Triage" => ExCalibur.Charters.IncidentTriage,
    "Contract Review" => ExCalibur.Charters.ContractReview,
    "Dependency Audit" => ExCalibur.Charters.DependencyAudit,
    "Dev Team" => ExCalibur.Charters.DevTeam
  }

  def charters, do: @charters

  def current_guild do
    import Ecto.Query

    alias ExCalibur.Schemas.Member

    names =
      ExCalibur.Repo.all(from(r in Member, where: r.type == "role", select: r.name))

    Enum.find_value(@charters, fn {guild_name, mod} ->
      meta = mod.metadata()
      role_names = Enum.map(meta.roles, & &1.name)

      if Enum.all?(role_names, &(&1 in names)) do
        {guild_name, mod}
      end
    end)
  end

  def evaluate(input_text, opts \\ []) do
    case current_guild() do
      nil ->
        {:error, :no_guild_installed}

      {_name, charter_mod} ->
        meta = charter_mod.metadata()

        ollama_url =
          Application.get_env(:ex_calibur, :ollama_url, "http://127.0.0.1:11434")

        ollama_api_key = Application.get_env(:ex_calibur, :ollama_api_key)

        provider = Keyword.get(opts, :provider, Ollama.new(base_url: ollama_url, api_key: ollama_api_key))

        roles = build_roles_from_charter(meta)
        actions_mod = build_actions_from_charter(meta)

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
            Phoenix.PubSub.broadcast(ExCalibur.PubSub, "evaluation:results", :refresh)
            {:approve, details}

          other ->
            other
        end
    end
  end

  defp build_roles_from_charter(meta) do
    Enum.map(meta.roles, fn role_def ->
      mod_name = Module.concat([ExCalibur, Roles, Macro.camelize(role_def.name)])

      if !Code.ensure_loaded?(mod_name) do
        contents =
          quote do
            use ExCalibur.Agent.Role

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
          LoadError ->
            Logger.error("Failed to load dependencies for role module #{inspect(mod_name)}",
              context: %{role_name: role_def.name, error_type: "LoadError"}
            )

            fallback_role_module(mod_name, role_def)

          CompileError ->
            Logger.error("Failed to compile role module #{inspect(mod_name)}",
              context: %{role_name: role_def.name, error_type: "CompileError"}
            )

            fallback_role_module(mod_name, role_def)

          error ->
            if Code.ensure_loaded?(mod_name) do
              :ok
            else
              Logger.error("Failed to create dynamic role module #{inspect(mod_name)}: #{inspect(error)}",
                context: %{role_name: role_def.name, error_type: Exception.message(error)}
              )

              fallback_role_module(mod_name, role_def)
            end
        end
      end

      mod_name
    end)
  end

  defp build_actions_from_charter(meta) do
    mod_name = Module.concat([ExCalibur, DynamicActions, :Template])

    if !Code.ensure_loaded?(mod_name) do
      action_defs =
        Enum.map(meta.actions, fn action ->
          quote do
            action(unquote(action))
          end
        end)

      contents =
        quote do
          use ExCalibur.Agent.Actions

          unquote_splicing(action_defs)
        end

      try do
        Module.create(mod_name, contents, Macro.Env.location(__ENV__))
      rescue
        LoadError ->
          Logger.error("Failed to load dependencies for actions module #{inspect(mod_name)}",
            context: %{actions: meta.actions, error_type: "LoadError"}
          )

          ExCalibur.DynamicActions.Template

        CompileError ->
          Logger.error("Failed to compile actions module #{inspect(mod_name)}",
            context: %{actions: meta.actions, error_type: "CompileError"}
          )

          ExCalibur.DynamicActions.Template

        error ->
          Logger.error("Failed to create dynamic actions module #{inspect(mod_name)}: #{inspect(error)}",
            context: %{actions: meta.actions, error_type: Exception.message(error)}
          )

          ExCalibur.DynamicActions.Template
      end
    end

    mod_name
  end

  defp fallback_role_module(mod_name, role_def) do
    # Create a minimal fallback role module that can be used when the main creation fails
    contents =
      quote do
        use ExCalibur.Agent.Role

        system_prompt("Fallback role for #{inspect(role_def.name)} - basic evaluation capabilities")

        # Add basic perspective as fallback
        perspective(:basic, model: "llama3", strategy: :default, name: "#{role_def.name}.fallback")

        def build_prompt(input, _context) do
          "Fallback evaluation for #{inspect(role_def.name)}:\n\n#{inspect(input)}"
        end
      end

    try do
      Module.create(mod_name, contents, Macro.Env.location(__ENV__))
    rescue
      error ->
        if Code.ensure_loaded?(mod_name) do
          :ok
        else
          Logger.error("Fallback role module creation also failed for #{inspect(mod_name)}: #{inspect(error)}",
            context: %{role_name: role_def.name, error_type: Exception.message(error)}
          )

          ExCalibur.Roles.Fallback
        end
    end
  end
end
