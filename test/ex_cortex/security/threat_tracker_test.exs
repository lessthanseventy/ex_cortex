defmodule ExCortex.Security.ThreatTrackerTest do
  use ExCortex.DataCase, async: false

  alias ExCortex.Security.ThreatTracker

  # ThreatTracker starts in application.ex base_children — always available

  setup do
    id = System.unique_integer([:positive])
    on_exit(fn -> ThreatTracker.clear(id) end)
    %{id: id}
  end

  describe "score tracking" do
    test "starts at 0.0 for unknown daydream" do
      assert ThreatTracker.score(-1) == 0.0
    end

    test "increments score", %{id: id} do
      ThreatTracker.increment(id, 3.0)
      assert ThreatTracker.score(id) == 3.0
    end

    test "accumulates multiple increments", %{id: id} do
      ThreatTracker.increment(id, 3.0)
      ThreatTracker.increment(id, 1.0)
      assert ThreatTracker.score(id) == 4.0
    end

    test "separate daydreams tracked independently", %{id: id} do
      id2 = id + 1
      ThreatTracker.increment(id, 5.0)
      ThreatTracker.increment(id2, 1.0)
      assert ThreatTracker.score(id) == 5.0
      assert ThreatTracker.score(id2) == 1.0
      ThreatTracker.clear(id2)
    end
  end

  describe "threshold checks" do
    test "below threshold returns :ok", %{id: id} do
      ThreatTracker.increment(id, 2.0)
      assert ThreatTracker.check(id) == :ok
    end

    test "at warn threshold returns :warn", %{id: id} do
      ThreatTracker.increment(id, 5.0)
      assert ThreatTracker.check(id) == :warn
    end

    test "at halt threshold returns :halt", %{id: id} do
      ThreatTracker.increment(id, 10.0)
      assert ThreatTracker.check(id) == :halt
    end
  end

  describe "cleanup" do
    test "clear removes score for daydream", %{id: id} do
      ThreatTracker.increment(id, 5.0)
      ThreatTracker.clear(id)
      assert ThreatTracker.score(id) == 0.0
    end
  end
end
