defmodule ExCalibur.Obsidian.SyncTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Obsidian.Sync

  test "sync_enabled? returns false when not configured" do
    # Since Settings.get reads from DB, in unit test context it returns nil
    # sync_enabled? should return false (nil != true)
    refute Sync.sync_enabled?()
  end

  test "vault_path returns nil when not configured" do
    assert Sync.vault_path() == nil
  end

  test "sync_lore_entry returns :skipped when not enabled" do
    fake_entry = %{
      title: "Test",
      body: "Body",
      tags: [],
      quest_id: 1,
      importance: 3,
      inserted_at: DateTime.utc_now()
    }

    assert Sync.sync_lore_entry(fake_entry) == :skipped
  end

  test "sync_lodge_card returns :skipped when not enabled" do
    fake_card = %{
      title: "Test Card",
      body: "Card body",
      type: "note",
      inserted_at: DateTime.utc_now()
    }

    assert Sync.sync_lodge_card(fake_card) == :skipped
  end
end
