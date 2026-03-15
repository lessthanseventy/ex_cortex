defmodule ExCortex.Thoughts.DebouncerTest do
  use ExCortex.DataCase, async: false

  alias ExCortex.Thoughts
  alias ExCortex.Thoughts.Debouncer

  test "enqueue_quest/3 accepts a thought without crashing" do
    {:ok, thought} =
      Thoughts.create_thought(%{
        name: "Debouncer Test Thought",
        trigger: "source",
        source_ids: ["src-test"]
      })

    items = [%ExCortex.Senses.Item{content: "test item", source_id: "src-test"}]

    # Should not crash
    assert :ok = Debouncer.enqueue_quest(thought, "test-source", items)
  end
end
