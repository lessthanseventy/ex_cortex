defmodule ExCalibur.LoreTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Lore

  test "create and list entries" do
    {:ok, _} = Lore.create_entry(%{title: "Test Entry", body: "hello", tags: ["a11y"]})
    entries = Lore.list_entries()
    assert length(entries) == 1
    assert hd(entries).title == "Test Entry"
  end

  test "list_entries filters by tags" do
    {:ok, _} = Lore.create_entry(%{title: "A11y", tags: ["a11y"]})
    {:ok, _} = Lore.create_entry(%{title: "Security", tags: ["security"]})
    entries = Lore.list_entries(tags: ["a11y"])
    assert length(entries) == 1
    assert hd(entries).title == "A11y"
  end

  test "write_artifact append mode creates new entries each time" do
    quest = %{id: 1, write_mode: "append"}
    {:ok, _} = Lore.write_artifact(quest, %{title: "Entry 1"})
    {:ok, _} = Lore.write_artifact(quest, %{title: "Entry 2"})
    entries = Lore.list_entries(quest_id: 1)
    assert length(entries) == 2
  end

  test "write_artifact replace mode overwrites quest-owned entry" do
    quest = %{id: 2, write_mode: "replace"}
    {:ok, _} = Lore.write_artifact(quest, %{title: "First"})
    {:ok, _} = Lore.write_artifact(quest, %{title: "Updated"})
    entries = Lore.list_entries(quest_id: 2)
    assert length(entries) == 1
    assert hd(entries).title == "Updated"
  end

  test "write_artifact both mode creates pinned summary and appends log" do
    quest = %{id: 10, write_mode: "both", name: "Test Quest", log_title_template: "Test Log — {date}"}
    {:ok, _} = Lore.write_artifact(quest, %{title: "Summary", source: "quest"})
    entries = Lore.list_entries(quest_id: 10)
    assert length(entries) == 2
    titles = Enum.map(entries, & &1.title)
    assert "Summary" in titles
    assert Enum.any?(titles, &String.starts_with?(&1, "Test Log"))
  end

  test "write_artifact both mode replaces summary but keeps appending log" do
    quest = %{id: 11, write_mode: "both", name: "Test Quest", log_title_template: "Log — {date}"}
    {:ok, _} = Lore.write_artifact(quest, %{title: "Summary", source: "quest"})
    {:ok, _} = Lore.write_artifact(quest, %{title: "Summary", source: "quest"})
    entries = Lore.list_entries(quest_id: 11)
    assert length(entries) == 3
  end

  test "write_artifact replace mode does not overwrite manually edited entry" do
    quest = %{id: 3, write_mode: "replace"}
    {:ok, entry} = Lore.write_artifact(quest, %{title: "Original"})
    # Simulate human edit
    {:ok, _} = Lore.update_entry(entry, %{title: "Human Edited", source: "manual"})
    # Quest tries to replace
    {:ok, _} = Lore.write_artifact(quest, %{title: "Quest Override"})
    entries = Lore.list_entries(quest_id: 3)
    # Human edit preserved, new entry appended
    assert length(entries) == 2
    titles = Enum.map(entries, & &1.title)
    assert "Human Edited" in titles
    assert "Quest Override" in titles
  end
end
