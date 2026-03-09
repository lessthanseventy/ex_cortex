defmodule ExCalibur.QuestDebouncerTest do
  use ExCalibur.DataCase, async: false

  alias ExCalibur.QuestDebouncer
  alias ExCalibur.Quests

  test "enqueue_campaign/3 accepts a campaign without crashing" do
    {:ok, campaign} =
      Quests.create_campaign(%{
        name: "Debouncer Test Campaign",
        trigger: "source",
        source_ids: ["src-test"]
      })

    items = [%ExCalibur.Sources.SourceItem{content: "test item", source_id: "src-test"}]

    # Should not crash
    assert :ok = QuestDebouncer.enqueue_campaign(campaign, "test-source", items)
  end
end
