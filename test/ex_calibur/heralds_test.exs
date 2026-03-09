defmodule ExCalibur.HeraldsTest do
  use ExCalibur.DataCase, async: true
  alias ExCalibur.Heralds
  alias ExCalibur.Heralds.Herald

  setup do
    ExCalibur.Repo.delete_all(Herald)
    :ok
  end

  test "create and list heralds" do
    {:ok, _} = Heralds.create_herald(%{name: "slack:eng", type: "slack", config: %{"webhook_url" => "https://hooks.slack.com/x"}})
    assert length(Heralds.list_heralds()) == 1
  end

  test "get_by_name returns ok tuple" do
    {:ok, _} = Heralds.create_herald(%{name: "slack:eng", type: "slack", config: %{}})
    assert {:ok, %{name: "slack:eng"}} = Heralds.get_by_name("slack:eng")
  end

  test "get_by_name returns error when missing" do
    assert {:error, :not_found} = Heralds.get_by_name("nope")
  end

  test "list_by_type filters correctly" do
    {:ok, _} = Heralds.create_herald(%{name: "slack:eng", type: "slack", config: %{}})
    {:ok, _} = Heralds.create_herald(%{name: "wh:main", type: "webhook", config: %{}})
    assert length(Heralds.list_by_type("slack")) == 1
  end

  test "delete_herald removes it" do
    {:ok, h} = Heralds.create_herald(%{name: "slack:eng", type: "slack", config: %{}})
    Heralds.delete_herald(h)
    assert Heralds.list_heralds() == []
  end

  test "changeset rejects invalid type" do
    assert {:error, _} = Heralds.create_herald(%{name: "x", type: "carrier-pigeon", config: %{}})
  end
end
