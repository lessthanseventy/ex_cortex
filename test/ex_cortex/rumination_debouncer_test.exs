defmodule ExCortex.Ruminations.DebouncerTest do
  use ExCortex.DataCase, async: false

  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Debouncer

  test "enqueue_rumination/3 accepts a rumination without crashing" do
    {:ok, rumination} =
      Ruminations.create_rumination(%{
        name: "Debouncer Test Rumination",
        trigger: "source",
        source_ids: ["src-test"]
      })

    items = [%ExCortex.Senses.Item{content: "test item", source_id: "src-test"}]

    # Should not crash
    assert :ok = Debouncer.enqueue_rumination(rumination, "test-source", items)
  end
end
