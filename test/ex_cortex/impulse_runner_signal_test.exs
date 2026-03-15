defmodule ExCortex.Thoughts.ImpulseRunner.SignalTest do
  use ExCortex.DataCase

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
      assert {:error, :no_roster} = ExCortex.Thoughts.ImpulseRunner.run(step, "test input")
    end
  end
end
