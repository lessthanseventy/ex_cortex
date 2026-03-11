defmodule ExCalibur.Lodge.CardTest do
  use ExCalibur.DataCase

  alias ExCalibur.Lodge.Card

  describe "changeset/2" do
    test "valid note card" do
      attrs = %{type: "note", title: "Test", body: "hello", status: "active", source: "manual"}
      changeset = Card.changeset(%Card{}, attrs)
      assert changeset.valid?
    end

    test "valid checklist card with metadata" do
      attrs = %{
        type: "checklist",
        title: "TODO",
        metadata: %{"items" => [%{"text" => "Buy milk", "checked" => false}]},
        status: "active",
        source: "manual"
      }

      changeset = Card.changeset(%Card{}, attrs)
      assert changeset.valid?
    end

    test "rejects invalid type" do
      attrs = %{type: "invalid", title: "Test", status: "active", source: "manual"}
      changeset = Card.changeset(%Card{}, attrs)
      refute changeset.valid?
    end

    test "rejects invalid status" do
      attrs = %{type: "note", title: "Test", status: "bogus", source: "manual"}
      changeset = Card.changeset(%Card{}, attrs)
      refute changeset.valid?
    end
  end
end
