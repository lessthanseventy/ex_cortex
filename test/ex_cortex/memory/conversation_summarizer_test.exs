defmodule ExCortex.Memory.ConversationSummarizerTest do
  use ExUnit.Case, async: true

  alias ExCortex.Memory.ConversationSummarizer

  describe "should_summarize?/1" do
    test "returns false for fewer than 3 thoughts" do
      refute ConversationSummarizer.should_summarize?([%{}, %{}])
    end

    test "returns true for 3+ thoughts" do
      thoughts = Enum.map(1..3, fn _ -> %{} end)
      assert ConversationSummarizer.should_summarize?(thoughts)
    end
  end

  describe "build_transcript/1" do
    test "formats thoughts into Q&A transcript" do
      thoughts = [
        %{question: "What is X?", answer: "X is Y.", inserted_at: ~N[2026-03-26 10:00:00]},
        %{question: "Why?", answer: "Because Z.", inserted_at: ~N[2026-03-26 10:01:00]}
      ]

      transcript = ConversationSummarizer.build_transcript(thoughts)
      assert transcript =~ "What is X?"
      assert transcript =~ "X is Y."
      assert transcript =~ "Why?"
    end
  end

  describe "compute_importance/1" do
    test "returns 2 for short sessions" do
      assert ConversationSummarizer.compute_importance(3) == 2
    end

    test "returns 3 for medium sessions" do
      assert ConversationSummarizer.compute_importance(6) == 3
    end

    test "returns 4 for long sessions" do
      assert ConversationSummarizer.compute_importance(10) == 4
    end
  end
end
