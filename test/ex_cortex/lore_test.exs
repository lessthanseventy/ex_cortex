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
    thought = %{id: 1, write_mode: "append"}
    {:ok, _} = Memory.write_artifact(thought, %{title: "Entry 1"})
    {:ok, _} = Memory.write_artifact(thought, %{title: "Entry 2"})
    engrams = Memory.list_engrams(thought_id: 1)
    assert length(engrams) == 2
  end

  test "write_artifact replace mode overwrites thought-owned engram" do
    thought = %{id: 2, write_mode: "replace"}
    {:ok, _} = Memory.write_artifact(thought, %{title: "First"})
    {:ok, _} = Memory.write_artifact(thought, %{title: "Updated"})
    engrams = Memory.list_engrams(thought_id: 2)
    assert length(engrams) == 1
    assert hd(engrams).title == "Updated"
  end

  test "write_artifact both mode creates pinned summary and appends log" do
    thought = %{id: 10, write_mode: "both", name: "Test Thought", log_title_template: "Test Log — {date}"}
    {:ok, _} = Memory.write_artifact(thought, %{title: "Summary", source: "thought"})
    engrams = Memory.list_engrams(thought_id: 10)
    assert length(engrams) == 2
    titles = Enum.map(engrams, & &1.title)
    assert "Summary" in titles
    assert Enum.any?(titles, &String.starts_with?(&1, "Test Log"))
  end

  test "write_artifact both mode replaces summary but keeps appending log" do
    thought = %{id: 11, write_mode: "both", name: "Test Thought", log_title_template: "Log — {date}"}
    {:ok, _} = Memory.write_artifact(thought, %{title: "Summary", source: "thought"})
    {:ok, _} = Memory.write_artifact(thought, %{title: "Summary", source: "thought"})
    engrams = Memory.list_engrams(thought_id: 11)
    assert length(engrams) == 3
  end

  test "write_artifact replace mode does not overwrite manually edited engram" do
    thought = %{id: 3, write_mode: "replace"}
    {:ok, engram} = Memory.write_artifact(thought, %{title: "Original"})
    # Simulate human edit
    {:ok, _} = Memory.update_engram(engram, %{title: "Human Edited", source: "manual"})
    # Thought tries to replace
    {:ok, _} = Memory.write_artifact(thought, %{title: "Thought Override"})
    engrams = Memory.list_engrams(thought_id: 3)
    # Human edit preserved, new engram appended
    assert length(engrams) == 2
    titles = Enum.map(engrams, & &1.title)
    assert "Human Edited" in titles
    assert "Thought Override" in titles
  end
end
