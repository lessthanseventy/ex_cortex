defmodule ExCalibur.QuestDebouncerTest do
  use ExCalibur.DataCase, async: false

  alias ExCalibur.QuestDebouncer
  alias ExCalibur.Quests

  test "enqueue_quest/3 accepts a quest without crashing" do
    {:ok, quest} =
      Quests.create_quest(%{
        name: "Debouncer Test Quest",
        trigger: "source",
        source_ids: ["src-test"]
      })

    items = [%ExCalibur.Sources.SourceItem{content: "test item", source_id: "src-test"}]

    # Should not crash
    assert :ok = QuestDebouncer.enqueue_quest(quest, "test-source", items)
  end
end
