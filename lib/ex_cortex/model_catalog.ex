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

  # Models known to handle structured tool calling properly.
  # Others may emit raw text instead of structured tool use.
  @tool_capable MapSet.new([
                  "claude_opus",
                  "claude_sonnet",
                  "claude_haiku",
                  "qwen3-coder",
                  "devstral-small-2:24b"
                ])

  @type model :: %{
          name: String.t(),
          tier: :master | :journeyman | :apprentice,
          provider: String.t(),
          tool_calling: boolean()
        }

  @doc "Returns all available models grouped by tier, most capable first."
  def grouped(opts \\ []) do
    models = if Keyword.get(opts, :tool_calling), do: tool_capable(), else: all()

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

  @doc "Returns only models known to handle structured tool calling."
  def tool_capable do
    Enum.filter(all(), & &1.tool_calling)
  end

  defp claude_models do
    if ExCortex.ClaudeClient.configured?() do
      [
        %{name: "claude_opus", tier: :master, provider: "claude", tool_calling: true},
        %{name: "claude_sonnet", tier: :master, provider: "claude", tool_calling: true},
        %{name: "claude_haiku", tier: :journeyman, provider: "claude", tool_calling: true}
      ]
    else
      []
    end
  end

  defp ollama_models do
    ExCortex.OllamaCache.get_models()
    |> Enum.map(fn name ->
      %{name: name, tier: tier_for(name), provider: "ollama", tool_calling: tool_capable?(name)}
    end)
    |> Enum.sort_by(fn m -> {tier_sort(m.tier), m.name} end)
  end

  defp tool_capable?(name) do
    # Check exact match or base model name (before the :tag)
    base = name |> String.split(":") |> List.first()
    MapSet.member?(@tool_capable, name) or MapSet.member?(@tool_capable, base)
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
