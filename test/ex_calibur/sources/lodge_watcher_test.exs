defmodule ExCalibur.Sources.LodgeWatcherTest do
  use ExCalibur.DataCase

  alias ExCalibur.Lodge
  alias ExCalibur.Sources.LodgeWatcher

  describe "init/1" do
    test "initializes with nil last_seen_at by default" do
      assert {:ok, %{last_seen_at: nil}} = LodgeWatcher.init(%{})
    end

    test "initializes with provided last_seen_at" do
      ts = "2026-03-11T00:00:00Z"
      assert {:ok, %{last_seen_at: ^ts}} = LodgeWatcher.init(%{"last_seen_at" => ts})
    end
  end

  describe "fetch/2" do
    test "returns all active cards on first fetch" do
      {:ok, _} = Lodge.create_card(%{type: "note", title: "Note 1", body: "body1", source: "manual"})
      {:ok, _} = Lodge.create_card(%{type: "alert", title: "Alert 1", body: "body2", source: "manual"})

      {:ok, state} = LodgeWatcher.init(%{})
      {:ok, items, new_state} = LodgeWatcher.fetch(state, %{})

      assert length(items) == 2
      assert Enum.all?(items, &(&1.type == "lodge_card"))
      assert new_state.last_seen_at
    end

    test "filters by type_filter" do
      {:ok, _} = Lodge.create_card(%{type: "note", title: "Note", body: "", source: "manual"})
      {:ok, _} = Lodge.create_card(%{type: "alert", title: "Alert", body: "", source: "manual"})

      {:ok, state} = LodgeWatcher.init(%{})
      {:ok, items, _} = LodgeWatcher.fetch(state, %{"type_filter" => ["note"]})

      assert length(items) == 1
      assert hd(items).metadata.card_type == "note"
    end

    test "filters by tag_filter" do
      {:ok, _} = Lodge.create_card(%{type: "note", title: "Tagged", body: "", source: "manual", tags: ["tech", "urgent"]})
      {:ok, _} = Lodge.create_card(%{type: "note", title: "Untagged", body: "", source: "manual"})

      {:ok, state} = LodgeWatcher.init(%{})
      {:ok, items, _} = LodgeWatcher.fetch(state, %{"tag_filter" => ["tech"]})

      assert length(items) == 1
      assert hd(items).metadata.title == "Tagged"
    end

    test "only returns cards updated after last_seen_at" do
      {:ok, _card1} = Lodge.create_card(%{type: "note", title: "Old", body: "", source: "manual"})

      # Use a checkpoint just before the first card's creation
      {:ok, state} = LodgeWatcher.init(%{})
      {:ok, items, new_state} = LodgeWatcher.fetch(state, %{})
      assert length(items) == 1

      # Create a new card after consuming the first
      Process.sleep(1100)
      {:ok, _} = Lodge.create_card(%{type: "note", title: "New", body: "", source: "manual"})

      {:ok, items, _} = LodgeWatcher.fetch(new_state, %{})

      assert length(items) == 1
      assert hd(items).metadata.title == "New"
    end

    test "returns empty list when no new cards" do
      {:ok, card} = Lodge.create_card(%{type: "note", title: "Existing", body: "", source: "manual"})

      {:ok, state} = LodgeWatcher.init(%{})
      {:ok, _items, new_state} = LodgeWatcher.fetch(state, %{})

      # Second fetch should return nothing new
      {:ok, items, _} = LodgeWatcher.fetch(new_state, %{})
      assert items == []

      # Update the card so it appears again - need to wait for different timestamp
      Process.sleep(1100)
      Lodge.update_card(card, %{body: "updated body"})
      {:ok, items, _} = LodgeWatcher.fetch(new_state, %{})
      assert length(items) == 1
    end

    test "populates source_item metadata correctly" do
      {:ok, _} =
        Lodge.create_card(%{
          type: "checklist",
          title: "My List",
          body: "items here",
          source: "manual",
          tags: ["todo"],
          pinned: true
        })

      {:ok, state} = LodgeWatcher.init(%{})
      {:ok, [item], _} = LodgeWatcher.fetch(state, %{"source_id" => "src-123"})

      assert item.source_id == "src-123"
      assert item.type == "lodge_card"
      assert item.content == "items here"
      assert item.metadata.card_type == "checklist"
      assert item.metadata.title == "My List"
      assert item.metadata.tags == ["todo"]
      assert item.metadata.pinned == true
    end
  end
end
