defmodule ExCortex.SettingsTest do
  use ExCortex.DataCase, async: false

  alias ExCortex.Settings

  describe "banner" do
    test "get_banner/0 returns nil when no settings exist" do
      assert Settings.get_banner() == nil
    end

    test "set_banner/1 stores and returns the banner" do
      assert {:ok, _} = Settings.set_banner("tech")
      assert Settings.get_banner() == "tech"
    end

    test "set_banner/1 updates existing banner" do
      {:ok, _} = Settings.set_banner("tech")
      {:ok, _} = Settings.set_banner("lifestyle")
      assert Settings.get_banner() == "lifestyle"
    end

    test "set_banner/1 validates banner value" do
      assert {:error, changeset} = Settings.set_banner("invalid")
      assert %{banner: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "config" do
    test "get/1 returns nil for unconfigured key" do
      assert Settings.get(:nonexistent_key_for_test) == nil
    end

    test "put/2 stores and get/1 retrieves" do
      Settings.put(:obsidian_vault, "MyVault")
      assert Settings.get(:obsidian_vault) == "MyVault"
    end

    test "put/2 overwrites existing value" do
      Settings.put(:obsidian_vault, "Old")
      Settings.put(:obsidian_vault, "New")
      assert Settings.get(:obsidian_vault) == "New"
    end
  end
end
