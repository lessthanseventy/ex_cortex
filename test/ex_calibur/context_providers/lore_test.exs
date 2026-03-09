defmodule ExCalibur.ContextProviders.LoreProviderTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.ContextProviders.Lore, as: LoreProvider
  alias ExCalibur.Lore

  test "returns empty string when no entries" do
    result = LoreProvider.build(%{"type" => "lore"}, %{}, "input")
    assert result == ""
  end

  test "injects entries as markdown context" do
    {:ok, _} = Lore.create_entry(%{title: "A11y news", body: "Some content", tags: ["a11y"], importance: 4})
    result = LoreProvider.build(%{"type" => "lore", "tags" => ["a11y"]}, %{}, "")
    assert result =~ "Lore Context"
    assert result =~ "A11y news"
    assert result =~ "importance: 4"
    assert result =~ "Some content"
  end

  test "respects limit" do
    for i <- 1..5 do
      Lore.create_entry(%{title: "Entry #{i}"})
    end

    result = LoreProvider.build(%{"type" => "lore", "limit" => 2}, %{}, "")
    assert length(Regex.scan(~r/### Entry/, result)) == 2
  end
end
