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

  describe "freeform output type" do
    test "run/2 returns :no_roster error when roster is empty" do
      quest = %ExCalibur.Quests.Quest{
        id: 10,
        name: "Freeform Quest",
        output_type: "freeform",
        roster: [],
        context_providers: []
      }

      assert {:error, :no_roster} = ExCalibur.QuestRunner.run(quest, "hello")
    end
  end

  describe "wildcard members" do
    test "wildcards includes freeform members and verdict-with-personality members" do
      wildcards = ExCalibur.Members.BuiltinMember.wildcards()
      ids = Enum.map(wildcards, & &1.id)

      assert "the-poet" in ids
      assert "the-historian" in ids
      assert "the-tabloid" in ids
      assert "the-intern" in ids
      assert "hype-detector" in ids
      assert "time-traveler" in ids
    end

    test "all wildcard members have category :wildcard" do
      assert Enum.all?(ExCalibur.Members.BuiltinMember.wildcards(), &(&1.category == :wildcard))
    end

    test "freeform members have system prompts without ACTION/CONFIDENCE/REASON format" do
      freeform_ids = ~w(the-poet the-historian the-tabloid)

      Enum.each(freeform_ids, fn id ->
        member = ExCalibur.Members.BuiltinMember.get(id)
        refute String.contains?(member.system_prompt, "ACTION:"),
               "#{id} should not have verdict format in system_prompt"
      end)
    end

    test "verdict wildcards include the response format" do
      verdict_ids = ~w(the-intern the-nitpicker the-optimist hype-detector the-philosopher time-traveler)

      Enum.each(verdict_ids, fn id ->
        member = ExCalibur.Members.BuiltinMember.get(id)
        assert String.contains?(member.system_prompt, "ACTION:"),
               "#{id} should include verdict format in system_prompt"
      end)
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
