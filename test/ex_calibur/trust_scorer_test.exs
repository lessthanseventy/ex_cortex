defmodule ExCalibur.TrustScorerTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.TrustScorer

  test "list_scores/0 returns empty list initially" do
    assert TrustScorer.list_scores() == []
  end

  test "decay/1 creates a score record at initial score below 1.0" do
    TrustScorer.decay("Alice")
    scores = TrustScorer.list_scores()
    assert length(scores) == 1
    [score] = scores
    assert score.member_name == "Alice"
    assert score.score < 1.0
    assert score.decay_count == 1
  end

  test "decay/1 called twice further reduces score" do
    TrustScorer.decay("Bob")
    TrustScorer.decay("Bob")
    [score] = TrustScorer.list_scores()
    assert score.decay_count == 2
    assert score.score < 0.97
  end

  test "record_run/1 decays members whose verdict contradicts step verdict" do
    steps = [
      %{
        verdict: "pass",
        results: [
          %{member: "Alice", verdict: "fail"},
          %{member: "Bob", verdict: "pass"}
        ]
      }
    ]

    TrustScorer.record_run(steps)
    # Give the async task time to complete in test
    Process.sleep(50)

    scores = TrustScorer.list_scores()
    alice = Enum.find(scores, &(&1.member_name == "Alice"))
    bob = Enum.find(scores, &(&1.member_name == "Bob"))

    assert alice
    assert alice.decay_count == 1
    assert bob == nil
  end
end
