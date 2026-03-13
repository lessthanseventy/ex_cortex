defmodule ExCalibur.Evaluator do
  @moduledoc false

  require Logger

  alias Excellence.LLM.Ollama
  alias Excellence.Orchestrator

  @charters %{
    "Content Moderation" => Excellence.Charters.ContentModeration,
    "Code Review" => Excellence.Charters.CodeReview,
    "Risk Assessment" => Excellence.Charters.RiskAssessment,
    "Accessibility Review" => Excellence.Charters.AccessibilityReview,
    "Performance Audit" => Excellence.Charters.PerformanceAudit,
    "Incident Triage" => Excellence.Charters.IncidentTriage,
    "Contract Review" => Excellence.Charters.ContractReview,
    "Dependency Audit" => Excellence.Charters.DependencyAudit,
    "Dev Team" => ExCalibur.Charters.DevTeam
  }

  def charters, do: @charters

  def current_guild do
    import Ecto.Query

    alias Excellence.Schemas.Member

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

        Orchestrator.evaluate(
          %{subject: input_text},
          %{},
          roles: roles,
          actions: actions_mod,
          strategy: meta.strategy,
          llm_provider: provider,
          guards: []
        )
    end
  end

  defp build_roles_from_charter(meta) do
    Enum.map(meta.roles, fn role_def ->
      mod_name = Module.concat([Excellence, Roles, Macro.camelize(role_def.name)])

      if !Code.ensure_loaded?(mod_name) do
        contents =
          quote do
            use Excellence.Role

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
          error ->
            Logger.error("Failed to create dynamic role module #{inspect(mod_name)}: #{inspect(error)}",
              context: %{role_name: role_def.name, error_type: Exception.message(error)}
            )
            # Fallback to a basic role module to prevent complete failure
            fallback_role_module(mod_name, role_def)
        end
      end

      mod_name
    end)
  end

  defp build_actions_from_charter(meta) do
    mod_name = Module.concat([Excellence, DynamicActions, :Template])

    if !Code.ensure_loaded?(mod_name) do
      action_defs =
        Enum.map(meta.actions, fn action ->
          quote do
            action(unquote(action))
          end
        end)

      contents =
        quote do
          use Excellence.Actions

          unquote_splicing(action_defs)
        end

      try do
        Module.create(mod_name, contents, Macro.Env.location(__ENV__))
      rescue
        error ->
          Logger.error("Failed to create dynamic actions module #{inspect(mod_name)}: #{inspect(error)}",
            context: %{actions: meta.actions, error_type: Exception.message(error)}
          )
          # Return a module that exists to prevent complete failure
          Excellence.DynamicActions.Template
      end
    end

    mod_name
  end

  defp fallback_role_module(mod_name, role_def) do
    # Create a minimal fallback role module that can be used when the main creation fails
    contents =
      quote do
        use Excellence.Role

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
        Logger.error("Fallback role module creation also failed for #{inspect(mod_name)}: #{inspect(error)}",
          context: %{role_name: role_def.name, error_type: Exception.message(error)}
        )
        # If fallback also fails, return a known working module
        Excellence.Roles.Fallback
    end
  end
end
