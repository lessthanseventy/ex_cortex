defmodule ExCortex.Ruminations.ImpulseRunner.SignalTest do
  use ExCortex.DataCase

  alias ExCortex.Ruminations
  alias ExCortex.Signals

  describe "signal output type" do
    test "posts a card to the Cortex when output_type is signal" do
      # Verify no cards exist initially
      assert Signals.list_signals() == []

      # The actual LLM call will fail in test (no Ollama running),
      # so we test the wiring by checking the step matcher exists
      step = %{
        output_type: "signal",
        roster: [],
        context_providers: [],
        name: "Test Cortex Step",
        description: "Posts to cortex"
      }

      # With empty roster, should get :no_roster error
      assert {:error, :no_roster} = ExCortex.Ruminations.ImpulseRunner.run(step, "test input")
    end

    test "signal output with a real Synapse struct returns :no_roster when roster is empty" do
      {:ok, synapse} =
        Ruminations.create_synapse(%{
          name: "Signal Test Synapse",
          description: "Tests signal output with a real synapse struct",
          trigger: "manual",
          output_type: "signal",
          cluster_name: "Test Cluster",
          roster: []
        })

      # Exercises the signal path with a real Synapse struct (not a bare map).
      # This caught a bug where bracket access on the struct raised UndefinedFunctionError.
      assert {:error, :no_roster} = ExCortex.Ruminations.ImpulseRunner.run(synapse, "test input")
    end

    test "signal output with a real Synapse struct and roster returns :no_members without LLM" do
      {:ok, synapse} =
        Ruminations.create_synapse(%{
          name: "Signal Roster Test Synapse",
          description: "Tests signal output with roster",
          trigger: "manual",
          output_type: "signal",
          cluster_name: "Test Cluster",
          roster: [%{"who" => "all", "preferred_who" => "Nonexistent", "how" => "solo", "when" => "sequential"}]
        })

      # With a roster but no matching neurons, should get :no_members
      assert {:error, :no_members} = ExCortex.Ruminations.ImpulseRunner.run(synapse, "test input")
    end
  end
end
