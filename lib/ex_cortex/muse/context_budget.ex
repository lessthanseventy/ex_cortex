defmodule ExCortex.Muse.ContextBudget do
  @moduledoc """
  Token-aware context budget allocation.

  Resolves model context window sizes and allocates token budgets
  across system prompt, context providers, history, and headroom.
  Per-model settings configurable in Instinct (tunable by neuroplasticity loop).
  """

  alias ExCortex.Settings

  defstruct [:total, :system, :context, :history, :headroom]

  @default_percentages %{system: 0.15, context: 0.45, history: 0.30, headroom: 0.10}

  @provider_weights %{
    "engrams" => 3,
    "obsidian" => 3,
    "signals" => 2,
    "email" => 2,
    "axioms" => 2,
    "axiom_search" => 2,
    "sources" => 1
  }

  @known_context_windows %{
    "ministral-3:8b" => 8_192,
    "devstral-small-2:24b" => 32_768,
    "claude_haiku" => 200_000,
    "claude_sonnet" => 200_000,
    "claude_opus" => 200_000
  }

  @doc "Allocate token budgets for a model."
  def allocate(model_id, opts \\ []) do
    total = Keyword.get(opts, :context_window) || context_window_for(model_id)
    percentages = Keyword.get(opts, :percentages) || resolve_percentages(model_id)

    %__MODULE__{
      total: total,
      system: trunc(total * percentages.system),
      context: trunc(total * percentages.context),
      history: trunc(total * percentages.history),
      headroom:
        total - trunc(total * percentages.system) - trunc(total * percentages.context) -
          trunc(total * percentages.history)
    }
  end

  @doc "Allocate per-provider token budgets from total context budget."
  def provider_budgets(providers, total_context_tokens) do
    weights =
      Enum.map(providers, fn %{"type" => type} ->
        {type, Map.get(@provider_weights, type, 1)}
      end)

    total_weight = Enum.reduce(weights, 0, fn {_type, w}, acc -> acc + w end)

    if total_weight == 0 do
      %{}
    else
      Map.new(weights, fn {type, weight} ->
        {type, trunc(weight / total_weight * total_context_tokens)}
      end)
    end
  end

  @doc "Estimate token count from text (byte_size / 4 heuristic)."
  def estimate_tokens(text) when is_binary(text), do: max(1, div(byte_size(text), 4))
  def estimate_tokens(_), do: 0

  @doc "Truncate text to fit within a token budget."
  def truncate_to_budget(text, token_budget) when is_binary(text) do
    char_budget = token_budget * 4

    if byte_size(text) <= char_budget do
      text
    else
      :telemetry.execute([:ex_cortex, :muse, :context_truncated], %{
        original_tokens: estimate_tokens(text),
        budget_tokens: token_budget
      })

      String.slice(text, 0, char_budget)
    end
  end

  defp context_window_for(model_id) do
    case Settings.resolve(:"context_window_#{model_id}", default: nil) do
      val when is_integer(val) -> val
      val when is_binary(val) -> String.to_integer(val)
      _ -> Map.get(@known_context_windows, model_id, 32_768)
    end
  end

  defp resolve_percentages(model_id) do
    Enum.reduce(@default_percentages, %{}, fn {key, default}, acc ->
      setting_key = :"context_budget_#{model_id}_#{key}"

      val =
        case Settings.resolve(setting_key, default: nil) do
          v when is_float(v) -> v
          v when is_binary(v) -> String.to_float(v)
          _ -> default
        end

      Map.put(acc, key, val)
    end)
  end
end
