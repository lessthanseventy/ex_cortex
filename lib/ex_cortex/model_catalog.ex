defmodule ExCortex.ModelCatalog do
  @moduledoc """
  Discovers available LLM models and categorizes them by capability tier.

  Tiers map to the neuron rank system:
  - master:      32b+ params, or Claude Opus/Sonnet
  - journeyman:  7b–31b params, or Claude Haiku
  - apprentice:  ≤4b params
  """

  @claude_tiers %{
    "claude_opus" => :master,
    "claude_sonnet" => :master,
    "claude_haiku" => :journeyman
  }

  @type model :: %{name: String.t(), tier: :master | :journeyman | :apprentice, provider: String.t()}

  @doc "Returns all available models grouped by tier, most capable first."
  def grouped do
    models = all()

    Enum.reject(
      [
        {"Master", Enum.filter(models, &(&1.tier == :master))},
        {"Journeyman", Enum.filter(models, &(&1.tier == :journeyman))},
        {"Apprentice", Enum.filter(models, &(&1.tier == :apprentice))}
      ],
      fn {_label, models} -> models == [] end
    )
  end

  @doc "Returns a flat list of all available models, sorted by capability."
  def all do
    claude_models() ++ ollama_models()
  end

  defp claude_models do
    if ExCortex.ClaudeClient.configured?() do
      [
        %{name: "claude_opus", tier: :master, provider: "claude"},
        %{name: "claude_sonnet", tier: :master, provider: "claude"},
        %{name: "claude_haiku", tier: :journeyman, provider: "claude"}
      ]
    else
      []
    end
  end

  defp ollama_models do
    ExCortex.OllamaCache.get_models()
    |> Enum.map(fn name -> %{name: name, tier: tier_for(name), provider: "ollama"} end)
    |> Enum.sort_by(fn m -> {tier_sort(m.tier), m.name} end)
  end

  @doc "Determine the tier for a model name."
  def tier_for(name) do
    case @claude_tiers[name] do
      nil -> tier_by_params(name)
      tier -> tier
    end
  end

  defp tier_by_params(name) do
    case Regex.run(~r/(\d+)b/, name) do
      [_, size] ->
        params = String.to_integer(size)

        cond do
          params >= 32 -> :master
          params >= 7 -> :journeyman
          true -> :apprentice
        end

      _ ->
        :journeyman
    end
  end

  defp tier_sort(:master), do: 0
  defp tier_sort(:journeyman), do: 1
  defp tier_sort(:apprentice), do: 2
end
