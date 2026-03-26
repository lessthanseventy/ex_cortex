defmodule ExCortex.Muse.ContextBudgetTest do
  use ExUnit.Case, async: true

  alias ExCortex.Muse.ContextBudget

  describe "allocate/1" do
    test "returns budget struct with correct proportions" do
      budget = ContextBudget.allocate("test-model", context_window: 32_768)

      assert budget.total == 32_768
      assert budget.system > 0
      assert budget.context > 0
      assert budget.history > 0
      assert budget.headroom > 0
      assert budget.system + budget.context + budget.history + budget.headroom == budget.total
    end

    test "applies custom percentages" do
      budget =
        ContextBudget.allocate("test-model",
          context_window: 10_000,
          percentages: %{system: 0.1, context: 0.6, history: 0.2, headroom: 0.1}
        )

      assert budget.context == 6_000
    end
  end

  describe "provider_budgets/2" do
    test "allocates proportionally by weight" do
      providers = [
        %{"type" => "engrams"},
        %{"type" => "obsidian"},
        %{"type" => "signals"}
      ]

      budgets = ContextBudget.provider_budgets(providers, 10_000)

      # engrams: weight 3, obsidian: weight 3, signals: weight 2 = total 8
      assert budgets["engrams"] == 3750
      assert budgets["obsidian"] == 3750
      assert budgets["signals"] == 2500
    end
  end

  describe "estimate_tokens/1" do
    test "estimates tokens from text" do
      text = String.duplicate("word ", 100)
      tokens = ContextBudget.estimate_tokens(text)
      assert tokens > 0
    end
  end

  describe "truncate_to_budget/2" do
    test "returns text unchanged if within budget" do
      text = "short text"
      assert ContextBudget.truncate_to_budget(text, 1000) == text
    end

    test "truncates text exceeding budget" do
      text = String.duplicate("a", 1000)
      result = ContextBudget.truncate_to_budget(text, 10)
      assert byte_size(result) <= 40
    end
  end
end
