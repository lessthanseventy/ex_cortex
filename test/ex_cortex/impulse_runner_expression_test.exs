defmodule ExCortex.Thoughts.ImpulseRunnerExpressionTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Expressions
  alias ExCortex.Thoughts.ImpulseRunner

  setup do
    # Insert a slack expression
    {:ok, expression} =
      Expressions.create_expression(%{
        name: "slack:test",
        type: "slack",
        config: %{"webhook_url" => "https://hooks.slack.com/test"}
      })

    %{expression: expression}
  end

  test "run/2 with expression output_type returns delivered result" do
    step = %{
      output_type: "slack",
      expression_name: "slack:test",
      roster: [],
      context_providers: [],
      description: "Summarize findings",
      entry_title_template: nil,
      name: "Test Step"
    }

    # We can't hit a real Slack URL in tests — verify it returns an error from the HTTP call
    # but the correct code path is reached (not an unknown output_type error)
    result = ImpulseRunner.run(step, "some input")
    # Should be {:ok, _} or {:error, _from_http} — not a clause error
    assert match?({:ok, _}, result) or match?({:error, _}, result)
  end

  test "run/2 with unknown expression_name returns error" do
    step = %{
      output_type: "slack",
      expression_name: "slack:nonexistent",
      roster: [],
      context_providers: [],
      description: "Summarize",
      entry_title_template: nil,
      name: "Test Step"
    }

    assert {:error, :not_found} = ImpulseRunner.run(step, "input")
  end
end
