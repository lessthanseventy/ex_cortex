defmodule ExCalibur.Sources.NextcloudWatcherTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Sources.NextcloudWatcher

  describe "init/1" do
    test "initializes with default state" do
      assert {:ok, %{last_activity_id: 0}} = NextcloudWatcher.init(%{})
    end

    test "uses config values when provided" do
      config = %{"last_activity_id" => 42}
      assert {:ok, %{last_activity_id: 42}} = NextcloudWatcher.init(config)
    end
  end

  describe "fetch/2" do
    test "returns error when url is missing" do
      {:ok, state} = NextcloudWatcher.init(%{})
      assert {:error, "url is required"} = NextcloudWatcher.fetch(state, %{})
    end
  end

  describe "stop/1" do
    test "returns :ok" do
      assert :ok = NextcloudWatcher.stop(%{})
    end
  end
end
