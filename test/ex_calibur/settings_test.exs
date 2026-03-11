defmodule ExCalibur.SettingsTest do
  use ExCalibur.DataCase

  alias ExCalibur.Settings

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
end
