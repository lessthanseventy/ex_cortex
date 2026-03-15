defmodule ExCortex.ContextProviders.LoreProviderTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.ContextProviders.Engrams, as: LoreProvider
  alias ExCortex.Memory

  test "returns empty string when no engrams" do
    result = LoreProvider.build(%{"type" => "memory"}, %{}, "input")
    assert result == ""
  end

  test "injects engrams as markdown context" do
    {:ok, _} = Memory.create_engram(%{title: "A11y news", body: "Some content", tags: ["a11y"], importance: 4})
    result = LoreProvider.build(%{"type" => "memory", "tags" => ["a11y"]}, %{}, "")
    assert result =~ "Memory Context"
    assert result =~ "A11y news"
    assert result =~ "importance: 4"
    assert result =~ "Some content"
  end

  test "respects limit" do
    for i <- 1..5 do
      Memory.create_engram(%{title: "Entry #{i}"})
    end

    result = LoreProvider.build(%{"type" => "memory", "limit" => 2}, %{}, "")
    assert length(Regex.scan(~r/### Entry/, result)) == 2
  end
end
