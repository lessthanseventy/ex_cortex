defmodule ExCortex.Signals.CardTest do
  use ExCortex.DataCase

  alias ExCortex.Signals.Signal

  describe "changeset/2" do
    test "valid note card" do
      attrs = %{type: "note", title: "Test", body: "hello", status: "active", source: "manual"}
      changeset = Signal.changeset(%Signal{}, attrs)
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

      changeset = Signal.changeset(%Signal{}, attrs)
      assert changeset.valid?
    end

    test "rejects invalid type" do
      attrs = %{type: "invalid", title: "Test", status: "active", source: "manual"}
      changeset = Signal.changeset(%Signal{}, attrs)
      refute changeset.valid?
    end

    test "rejects invalid status" do
      attrs = %{type: "note", title: "Test", status: "bogus", source: "manual"}
      changeset = Signal.changeset(%Signal{}, attrs)
      refute changeset.valid?
    end
  end
end
