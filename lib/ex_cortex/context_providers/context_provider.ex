defmodule ExCortex.ContextProviders.ContextProvider do
  @moduledoc """
  Behaviour for context providers — modules that supply additional context
  to inject into the prompt preamble before evaluation.

  Each provider receives the thought and input text, and returns a string
  to prepend to the user message.

  ## Provider config map format (stored on Thought)
    %{"type" => "static", "content" => "Always consider..."}
    %{"type" => "rumination_history", "limit" => 5}
    %{"type" => "neuron_stats"}
  """

  @callback build(config :: map(), thought :: map(), input :: String.t()) :: String.t()

  @doc """
  Assemble all context strings from a list of provider configs.
  Returns a single string to prepend, or "" if none.
  """
  def assemble(providers, thought, input) when is_list(providers) do
    providers
    |> Enum.map(&build_one(&1, thought, input))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  def assemble(_, _, _), do: ""

  @doc """
  Assemble context with token-aware budgeting.
  Each provider gets a weighted share of the total budget, with unused
  tokens cascading to subsequent providers.
  """
  def assemble(providers, thought, input, budget_tokens) when is_list(providers) and is_integer(budget_tokens) do
    alias ExCortex.Muse.ContextBudget

    budgets = ContextBudget.provider_budgets(providers, budget_tokens)

    {results, _remaining} =
      Enum.reduce(providers, {[], budget_tokens}, fn provider, {acc, remaining} ->
        type = Map.get(provider, "type", "unknown")
        provider_budget = Map.get(budgets, type, remaining)
        text = build_one(provider, thought, input)

        if text == "" do
          {acc, remaining}
        else
          truncated = ContextBudget.truncate_to_budget(text, min(provider_budget, remaining))
          used = ContextBudget.estimate_tokens(truncated)
          {[truncated | acc], remaining - used}
        end
      end)

    results
    |> Enum.reverse()
    |> Enum.join("\n\n")
  end

  defp build_one(%{"type" => type} = config, thought, input) do
    mod = module_for(type)

    if mod do
      try do
        apply(mod, :build, [config, thought, input])
      rescue
        _ -> ""
      end
    else
      ""
    end
  end

  defp build_one(_, _, _), do: ""

  defp module_for("static"), do: Module.concat([ExCortex, ContextProviders, Static])

  defp module_for("rumination_history"), do: Module.concat([ExCortex, ContextProviders, RuminationHistory])

  defp module_for("neuron_stats"), do: Module.concat([ExCortex, ContextProviders, NeuronStats])

  defp module_for("memory"), do: Module.concat([ExCortex, ContextProviders, Memory])

  defp module_for("cluster_pathway"), do: Module.concat([ExCortex, ContextProviders, ClusterPathway])

  defp module_for("axiom"), do: Module.concat([ExCortex, ContextProviders, Axiom])

  defp module_for("sandbox"), do: Module.concat([ExCortex, ContextProviders, Sandbox])

  defp module_for("file_reader"), do: Module.concat([ExCortex, ContextProviders, FileReader])

  defp module_for("github_issues"), do: Module.concat([ExCortex, ContextProviders, GithubIssues])

  defp module_for("app_telemetry"), do: Module.concat([ExCortex, ContextProviders, AppTelemetry])

  defp module_for("pr_diff"), do: Module.concat([ExCortex, ContextProviders, PrDiff])

  defp module_for("git_log"), do: Module.concat([ExCortex, ContextProviders, GitLog])

  defp module_for("rumination_output"), do: Module.concat([ExCortex, ContextProviders, RuminationOutput])

  defp module_for("test_failures"), do: Module.concat([ExCortex, ContextProviders, TestFailures])

  defp module_for("neuron_roster"), do: Module.concat([ExCortex, ContextProviders, NeuronRoster])

  defp module_for("signals"), do: Module.concat([ExCortex, ContextProviders, Signals])

  defp module_for("axiom_search"), do: Module.concat([ExCortex, ContextProviders, AxiomSearch])

  defp module_for("obsidian"), do: Module.concat([ExCortex, ContextProviders, Obsidian])

  defp module_for("email"), do: Module.concat([ExCortex, ContextProviders, Email])

  defp module_for("sources"), do: Module.concat([ExCortex, ContextProviders, Sources])

  defp module_for("engrams"), do: Module.concat([ExCortex, ContextProviders, Engrams])

  defp module_for("agents_md"), do: Module.concat([ExCortex, ContextProviders, AgentsMd])

  defp module_for(_), do: nil
end
