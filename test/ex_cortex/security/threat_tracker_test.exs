defmodule ExCortex.Security.ThreatTrackerTest do
  use ExUnit.Case, async: true

  alias ExCortex.Security.ThreatTracker

  setup do
    tracker = start_supervised!(ThreatTracker)
    %{tracker: tracker}
  end

  describe "score tracking" do
    test "starts at 0.0 for unknown daydream" do
      assert ThreatTracker.score(999) == 0.0
    end

    test "increments score" do
      ThreatTracker.increment(1, 3.0)
      assert ThreatTracker.score(1) == 3.0
    end

    test "accumulates multiple increments" do
      ThreatTracker.increment(1, 3.0)
      ThreatTracker.increment(1, 1.0)
      assert ThreatTracker.score(1) == 4.0
    end

    test "separate daydreams tracked independently" do
      ThreatTracker.increment(1, 5.0)
      ThreatTracker.increment(2, 1.0)
      assert ThreatTracker.score(1) == 5.0
      assert ThreatTracker.score(2) == 1.0
    end
  end

  describe "threshold checks" do
    test "below threshold returns :ok" do
      ThreatTracker.increment(1, 2.0)
      assert ThreatTracker.check(1) == :ok
    end

    test "at warn threshold returns :warn" do
      ThreatTracker.increment(1, 5.0)
      assert ThreatTracker.check(1) == :warn
    end

    test "at halt threshold returns :halt" do
      ThreatTracker.increment(1, 10.0)
      assert ThreatTracker.check(1) == :halt
    end
  end

  describe "cleanup" do
    test "clear removes score for daydream" do
      ThreatTracker.increment(1, 5.0)
      ThreatTracker.clear(1)
      assert ThreatTracker.score(1) == 0.0
    end
  end
end
