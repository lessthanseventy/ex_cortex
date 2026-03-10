defmodule ExCalibur.StepRunnerTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Members.BuiltinMember
  alias ExCalibur.Quests.Step

  describe "model fallback chains" do
    test "fallback_models_for/2 returns assigned model first, then chain" do
      assigned = "missing-model"
      chain = ["phi4-mini", "gemma3:4b"]
      result = ExCalibur.StepRunner.fallback_models_for(assigned, chain)
      assert result == ["missing-model", "phi4-mini", "gemma3:4b"]
    end

    test "fallback_models_for/2 deduplicates when assigned model is in chain" do
      assigned = "phi4-mini"
      chain = ["phi4-mini", "gemma3:4b"]
      result = ExCalibur.StepRunner.fallback_models_for(assigned, chain)
      assert result == ["phi4-mini", "gemma3:4b"]
    end
  end

  describe "challenger member" do
    test "BuiltinMember.get/1 returns a challenger spec" do
      member = BuiltinMember.get("challenger")
      assert member
      assert member.id == "challenger"
      assert member.category == :validator
      assert String.contains?(member.system_prompt, "evidence")
    end
  end

  describe "freeform output type" do
    test "run/2 returns :no_roster error when roster is empty" do
      step = %Step{
        id: 10,
        name: "Freeform Step",
        output_type: "freeform",
        roster: [],
        context_providers: []
      }

      assert {:error, :no_roster} = ExCalibur.StepRunner.run(step, "hello")
    end
  end

  describe "wildcard members" do
    test "wildcards includes freeform members and verdict-with-personality members" do
      wildcards = BuiltinMember.wildcards()
      ids = Enum.map(wildcards, & &1.id)

      assert "the-poet" in ids
      assert "the-historian" in ids
      assert "the-tabloid" in ids
      assert "the-intern" in ids
      assert "hype-detector" in ids
      assert "time-traveler" in ids
    end

    test "all wildcard members have category :wildcard" do
      assert Enum.all?(BuiltinMember.wildcards(), &(&1.category == :wildcard))
    end

    test "freeform members have system prompts without ACTION/CONFIDENCE/REASON format" do
      freeform_ids = ~w(the-poet the-historian the-tabloid)

      Enum.each(freeform_ids, fn id ->
        member = BuiltinMember.get(id)

        refute String.contains?(member.system_prompt, "ACTION:"),
               "#{id} should not have verdict format in system_prompt"
      end)
    end

    test "verdict wildcards include the response format" do
      verdict_ids = ~w(the-intern the-nitpicker the-optimist hype-detector the-philosopher time-traveler)

      Enum.each(verdict_ids, fn id ->
        member = BuiltinMember.get(id)

        assert String.contains?(member.system_prompt, "ACTION:"),
               "#{id} should include verdict format in system_prompt"
      end)
    end
  end

  describe "rank-gated eligibility" do
    test "run/2 returns rank_insufficient when no members meet min_rank" do
      step = %Step{
        id: 1,
        name: "Gated Step",
        min_rank: "master",
        roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}],
        context_providers: [],
        output_type: "verdict"
      }

      assert {:error, {:rank_insufficient, _reason}} = ExCalibur.StepRunner.run(step, "input")
    end

    test "run/2 proceeds normally when min_rank is nil" do
      step = %Step{
        id: 2,
        name: "Open Step",
        min_rank: nil,
        roster: [],
        context_providers: [],
        output_type: "verdict"
      }

      result = ExCalibur.StepRunner.run(step, "input")
      assert result != {:error, {:rank_insufficient, "Step requires master or higher — no eligible members found"}}
    end
  end
end
