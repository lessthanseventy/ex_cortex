defmodule ExCalibur.QuestRunnerTest do
  use ExCalibur.DataCase, async: true

  describe "model fallback chains" do
    test "fallback_models_for/2 returns assigned model first, then chain" do
      assigned = "missing-model"
      chain = ["phi4-mini", "gemma3:4b"]
      result = ExCalibur.QuestRunner.fallback_models_for(assigned, chain)
      assert result == ["missing-model", "phi4-mini", "gemma3:4b"]
    end

    test "fallback_models_for/2 deduplicates when assigned model is in chain" do
      assigned = "phi4-mini"
      chain = ["phi4-mini", "gemma3:4b"]
      result = ExCalibur.QuestRunner.fallback_models_for(assigned, chain)
      assert result == ["phi4-mini", "gemma3:4b"]
    end
  end

  describe "challenger member" do
    test "BuiltinMember.get/1 returns a challenger spec" do
      member = ExCalibur.Members.BuiltinMember.get("challenger")
      assert member != nil
      assert member.id == "challenger"
      assert member.category == :validator
      assert String.contains?(member.system_prompt, "evidence")
    end
  end

  describe "rank-gated eligibility" do
    test "run/2 returns rank_insufficient when no members meet min_rank" do
      quest = %ExCalibur.Quests.Quest{
        id: 1,
        name: "Gated Quest",
        min_rank: "master",
        roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}],
        context_providers: [],
        output_type: "verdict"
      }

      assert {:error, {:rank_insufficient, _reason}} = ExCalibur.QuestRunner.run(quest, "input")
    end

    test "run/2 proceeds normally when min_rank is nil" do
      quest = %ExCalibur.Quests.Quest{
        id: 2,
        name: "Open Quest",
        min_rank: nil,
        roster: [],
        context_providers: [],
        output_type: "verdict"
      }

      result = ExCalibur.QuestRunner.run(quest, "input")
      assert result != {:error, {:rank_insufficient, "Quest requires master or higher — no eligible members found"}}
    end
  end
end
