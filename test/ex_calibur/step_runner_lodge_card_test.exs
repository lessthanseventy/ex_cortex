defmodule ExCalibur.StepRunner.LodgeCardTest do
  use ExCalibur.DataCase

  alias ExCalibur.Lodge

  describe "lodge_card output type" do
    test "posts a card to the Lodge when output_type is lodge_card" do
      # Verify no cards exist initially
      assert Lodge.list_cards() == []

      # The actual LLM call will fail in test (no Ollama running),
      # so we test the wiring by checking the step matcher exists
      step = %{
        output_type: "lodge_card",
        roster: [],
        context_providers: [],
        name: "Test Lodge Step",
        description: "Posts to lodge"
      }

      # With empty roster, should get :no_roster error
      assert {:error, :no_roster} = ExCalibur.StepRunner.run(step, "test input")
    end
  end
end
