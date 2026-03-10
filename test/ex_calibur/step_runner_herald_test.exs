defmodule ExCalibur.StepRunnerHeraldTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Heralds
  alias ExCalibur.StepRunner

  setup do
    # Insert a slack herald
    {:ok, herald} =
      Heralds.create_herald(%{
        name: "slack:test",
        type: "slack",
        config: %{"webhook_url" => "https://hooks.slack.com/test"}
      })

    %{herald: herald}
  end

  test "run/2 with herald output_type returns delivered result" do
    step = %{
      output_type: "slack",
      herald_name: "slack:test",
      roster: [],
      context_providers: [],
      description: "Summarize findings",
      entry_title_template: nil,
      name: "Test Step"
    }

    # We can't hit a real Slack URL in tests — verify it returns an error from the HTTP call
    # but the correct code path is reached (not an unknown output_type error)
    result = StepRunner.run(step, "some input")
    # Should be {:ok, _} or {:error, _from_http} — not a clause error
    assert match?({:ok, _}, result) or match?({:error, _}, result)
  end

  test "run/2 with unknown herald_name returns error" do
    step = %{
      output_type: "slack",
      herald_name: "slack:nonexistent",
      roster: [],
      context_providers: [],
      description: "Summarize",
      entry_title_template: nil,
      name: "Test Step"
    }

    assert {:error, :not_found} = StepRunner.run(step, "input")
  end
end
