defmodule ExCortex.Memory.TierGeneratorTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Memory
  alias ExCortex.Memory.TierGenerator

  test "returns :no_body for empty engrams" do
    {:ok, engram} = Memory.create_engram(%{title: "Empty", body: ""})
    assert {:error, :no_body} = TierGenerator.generate(engram)
  end

  test "returns :no_body for nil body" do
    {:ok, engram} = Memory.create_engram(%{title: "Nil body"})
    # body defaults to "" in schema
    assert {:error, :no_body} = TierGenerator.generate(engram)
  end
end
