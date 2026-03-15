defmodule ExCortex.Thoughts.ImpulseRunnerTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Neurons.Builtin
  alias ExCortex.Thoughts.ImpulseRunner
  alias ExCortex.Thoughts.Synapse

  describe "model fallback chains" do
    test "fallback_models_for/2 returns assigned model first, then chain" do
      assigned = "missing-model"
      chain = ["phi4-mini", "gemma3:4b"]
      result = ImpulseRunner.fallback_models_for(assigned, chain)
      assert result == ["missing-model", "phi4-mini", "gemma3:4b"]
    end

    test "fallback_models_for/2 deduplicates when assigned model is in chain" do
      assigned = "phi4-mini"
      chain = ["phi4-mini", "gemma3:4b"]
      result = ImpulseRunner.fallback_models_for(assigned, chain)
      assert result == ["phi4-mini", "gemma3:4b"]
    end
  end

  describe "challenger neuron" do
    test "Builtin.get/1 returns a challenger spec" do
      neuron = Builtin.get("challenger")
      assert neuron
      assert neuron.id == "challenger"
      assert neuron.category == :validator
      assert String.contains?(neuron.system_prompt, "evidence")
    end
  end

  describe "freeform output type" do
    test "run/2 returns :no_roster error when roster is empty" do
      step = %Synapse{
        id: 10,
        name: "Freeform Step",
        output_type: "freeform",
        roster: [],
        context_providers: []
      }

      assert {:error, :no_roster} = ImpulseRunner.run(step, "hello")
    end
  end

  describe "wildcard neurons" do
    test "wildcards includes freeform neurons and verdict-with-personality neurons" do
      wildcards = Builtin.wildcards()
      ids = Enum.map(wildcards, & &1.id)

      assert "the-poet" in ids
      assert "the-historian" in ids
      assert "the-tabloid" in ids
      assert "the-intern" in ids
      assert "hype-detector" in ids
      assert "time-traveler" in ids
    end

    test "all wildcard neurons have category :wildcard" do
      assert Enum.all?(Builtin.wildcards(), &(&1.category == :wildcard))
    end

    test "freeform neurons have system prompts without ACTION/CONFIDENCE/REASON format" do
      freeform_ids = ~w(the-poet the-historian the-tabloid)

      Enum.each(freeform_ids, fn id ->
        neuron = Builtin.get(id)

        refute String.contains?(neuron.system_prompt, "ACTION:"),
               "#{id} should not have verdict format in system_prompt"
      end)
    end

    test "verdict wildcards include the response format" do
      verdict_ids = ~w(the-intern the-nitpicker the-optimist hype-detector the-philosopher time-traveler)

      Enum.each(verdict_ids, fn id ->
        neuron = Builtin.get(id)

        assert String.contains?(neuron.system_prompt, "ACTION:"),
               "#{id} should include verdict format in system_prompt"
      end)
    end
  end

  describe "rank-gated eligibility" do
    test "run/2 returns rank_insufficient when no neurons meet min_rank" do
      step = %Synapse{
        id: 1,
        name: "Gated Step",
        min_rank: "master",
        roster: [%{"who" => "all", "when" => "sequential", "how" => "solo"}],
        context_providers: [],
        output_type: "verdict"
      }

      assert {:error, {:rank_insufficient, _reason}} = ImpulseRunner.run(step, "input")
    end

    test "run/2 proceeds normally when min_rank is nil" do
      step = %Synapse{
        id: 2,
        name: "Open Step",
        min_rank: nil,
        roster: [],
        context_providers: [],
        output_type: "verdict"
      }

      result = ImpulseRunner.run(step, "input")
      assert result != {:error, {:rank_insufficient, "Step requires master or higher — no eligible neurons found"}}
    end
  end

  describe "escalate mode" do
    test "run/2 with escalate: true and no neurons returns abstain verdict" do
      step = %Synapse{
        id: 99,
        name: "Escalate Test",
        output_type: "verdict",
        roster: [%{"who" => "apprentice", "how" => "solo", "when" => "sequential"}],
        escalate: true,
        escalate_threshold: 0.9,
        context_providers: []
      }

      result = ImpulseRunner.run(step, "test input")
      assert match?({:ok, %{verdict: _}}, result)
    end

    test "run/2 without escalate: true behaves as before" do
      step = %Synapse{
        id: 100,
        name: "No Escalate",
        output_type: "verdict",
        roster: [],
        escalate: false,
        context_providers: []
      }

      assert {:ok, %{verdict: "pass"}} = ImpulseRunner.run(step, "test")
    end
  end

  describe "reflect mode" do
    test "run/2 with loop_mode: reflect and no tools returns normal result" do
      step = %Synapse{
        id: 101,
        name: "Reflect Test",
        output_type: "verdict",
        roster: [],
        loop_mode: "reflect",
        loop_tools: [],
        reflect_threshold: 0.9,
        context_providers: []
      }

      assert {:ok, %{verdict: "pass"}} = ImpulseRunner.run(step, "test")
    end
  end
end
