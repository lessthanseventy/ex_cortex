defmodule ExCalibur.GuildChartersTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.GuildCharters

  test "upsert_charter/2 creates a charter for a guild" do
    assert {:ok, charter} = GuildCharters.upsert_charter("TestGuild", "Our values: honesty.")
    assert charter.guild_name == "TestGuild"
    assert charter.charter_text == "Our values: honesty."
  end

  test "upsert_charter/2 updates an existing charter" do
    {:ok, _} = GuildCharters.upsert_charter("TestGuild", "v1")
    {:ok, updated} = GuildCharters.upsert_charter("TestGuild", "v2")
    assert updated.charter_text == "v2"
  end

  test "get_charter/1 returns nil when no charter exists" do
    assert GuildCharters.get_charter("NoSuchGuild") == nil
  end

  test "get_charter/1 returns charter text when it exists" do
    {:ok, _} = GuildCharters.upsert_charter("MyGuild", "Be excellent.")
    assert GuildCharters.get_charter("MyGuild") == "Be excellent."
  end
end
