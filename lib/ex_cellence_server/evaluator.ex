defmodule ExCellenceServer.Evaluator do
  @moduledoc false

  alias Excellence.LLM.Ollama
  alias Excellence.Orchestrator

  @charters %{
    "Content Moderation" => Excellence.Charters.ContentModeration,
    "Code Review" => Excellence.Charters.CodeReview,
    "Risk Assessment" => Excellence.Charters.RiskAssessment
  }

  def charters, do: @charters

  def evaluate(guild_name, input_text, opts \\ []) do
    charter_mod = Map.fetch!(@charters, guild_name)
    meta = charter_mod.metadata()

    ollama_url = Application.get_env(:ex_cellence_server, :ollama_url, "http://127.0.0.1:11434")
    provider = Keyword.get(opts, :provider, Ollama.new(base_url: ollama_url))

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

        Module.create(mod_name, contents, Macro.Env.location(__ENV__))
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

      Module.create(mod_name, contents, Macro.Env.location(__ENV__))
    end

    mod_name
  end
end
