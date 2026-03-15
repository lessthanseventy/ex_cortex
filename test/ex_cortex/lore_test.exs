defmodule ExCortex.LoreTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Memory

  test "create and list engrams" do
    {:ok, _} = Memory.create_engram(%{title: "Test Entry", body: "hello", tags: ["a11y"]})
    engrams = Memory.list_engrams()
    assert length(engrams) == 1
    assert hd(engrams).title == "Test Entry"
  end

  test "list_engrams filters by tags" do
    {:ok, _} = Memory.create_engram(%{title: "A11y", tags: ["a11y"]})
    {:ok, _} = Memory.create_engram(%{title: "Security", tags: ["security"]})
    engrams = Memory.list_engrams(tags: ["a11y"])
    assert length(engrams) == 1
    assert hd(engrams).title == "A11y"
  end

  test "write_artifact append mode creates new engrams each time" do
    rumination = %{id: 1, write_mode: "append"}
    {:ok, _} = Memory.write_artifact(rumination, %{title: "Entry 1"})
    {:ok, _} = Memory.write_artifact(rumination, %{title: "Entry 2"})
    engrams = Memory.list_engrams(rumination_id: 1)
    assert length(engrams) == 2
  end

  test "write_artifact replace mode overwrites rumination-owned engram" do
    rumination = %{id: 2, write_mode: "replace"}
    {:ok, _} = Memory.write_artifact(rumination, %{title: "First"})
    {:ok, _} = Memory.write_artifact(rumination, %{title: "Updated"})
    engrams = Memory.list_engrams(rumination_id: 2)
    assert length(engrams) == 1
    assert hd(engrams).title == "Updated"
  end

  test "write_artifact both mode creates pinned summary and appends log" do
    rumination = %{id: 10, write_mode: "both", name: "Test Rumination", log_title_template: "Test Log — {date}"}
    {:ok, _} = Memory.write_artifact(rumination, %{title: "Summary", source: "thought"})
    engrams = Memory.list_engrams(rumination_id: 10)
    assert length(engrams) == 2
    titles = Enum.map(engrams, & &1.title)
    assert "Summary" in titles
    assert Enum.any?(titles, &String.starts_with?(&1, "Test Log"))
  end

  test "write_artifact both mode replaces summary but keeps appending log" do
    rumination = %{id: 11, write_mode: "both", name: "Test Rumination", log_title_template: "Log — {date}"}
    {:ok, _} = Memory.write_artifact(rumination, %{title: "Summary", source: "thought"})
    {:ok, _} = Memory.write_artifact(rumination, %{title: "Summary", source: "thought"})
    engrams = Memory.list_engrams(rumination_id: 11)
    assert length(engrams) == 3
  end

  test "write_artifact replace mode does not overwrite manually edited engram" do
    rumination = %{id: 3, write_mode: "replace"}
    {:ok, engram} = Memory.write_artifact(rumination, %{title: "Original"})
    # Simulate human edit
    {:ok, _} = Memory.update_engram(engram, %{title: "Human Edited", source: "manual"})
    # Rumination tries to replace
    {:ok, _} = Memory.write_artifact(rumination, %{title: "Rumination Override"})
    engrams = Memory.list_engrams(rumination_id: 3)
    # Human edit preserved, new engram appended
    assert length(engrams) == 2
    titles = Enum.map(engrams, & &1.title)
    assert "Human Edited" in titles
    assert "Rumination Override" in titles
  end
end
