defmodule ExCortex.Expressions.CorrelationTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Expressions.Correlation

  test "changeset validates required fields" do
    cs = Correlation.changeset(%Correlation{}, %{})
    refute cs.valid?
    assert "can't be blank" in errors_on(cs).expression_id
    assert "can't be blank" in errors_on(cs).daydream_id
    assert "can't be blank" in errors_on(cs).external_ref
  end

  test "changeset accepts valid attrs" do
    cs =
      Correlation.changeset(%Correlation{}, %{
        expression_id: 1,
        daydream_id: 1,
        external_ref: "slack-thread-123"
      })

    assert cs.valid?
  end

  test "synapse_id is optional" do
    cs =
      Correlation.changeset(%Correlation{}, %{
        expression_id: 1,
        daydream_id: 1,
        external_ref: "ref-123",
        synapse_id: 5
      })

    assert cs.valid?
  end
end
