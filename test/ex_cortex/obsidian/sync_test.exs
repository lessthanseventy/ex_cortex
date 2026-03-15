defmodule ExCortex.Obsidian.SyncTest do
  use ExCortex.DataCase, async: false

  alias ExCortex.Obsidian.Sync
  alias ExCortex.Settings

  setup do
    # Ensure obsidian is not configured for these tests
    prev_sync = Settings.get(:obsidian_sync_enabled)
    prev_vault = Settings.get(:obsidian_vault_path)
    Settings.put(:obsidian_sync_enabled, nil)
    Settings.put(:obsidian_vault_path, nil)

    on_exit(fn ->
      Settings.put(:obsidian_sync_enabled, prev_sync)
      Settings.put(:obsidian_vault_path, prev_vault)
    end)

    :ok
  end

  test "sync_enabled? returns false when not configured" do
    refute Sync.sync_enabled?()
  end

  test "vault_path returns nil when not configured" do
    assert Sync.vault_path() == nil
  end

  test "sync_engram returns :skipped when not enabled" do
    fake_entry = %{
      title: "Test",
      body: "Body",
      tags: [],
      thought_id: 1,
      importance: 3,
      inserted_at: DateTime.utc_now()
    }

    assert Sync.sync_engram(fake_entry) == :skipped
  end

  test "sync_signal returns :skipped when not enabled" do
    fake_card = %{
      title: "Test Card",
      body: "Card body",
      type: "note",
      inserted_at: DateTime.utc_now()
    }

    assert Sync.sync_signal(fake_card) == :skipped
  end
end
