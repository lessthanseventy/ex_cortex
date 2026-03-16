defmodule ExCortex.MuseTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Muse

  describe "gather_context/2" do
    test "returns source context even when no engrams or axioms match" do
      context = Muse.gather_context("xyzzy_nonexistent_query_12345")
      assert context =~ "Available Data Sources"
    end

    test "includes matching engrams" do
      {:ok, _} =
        ExCortex.Memory.create_engram(%{
          title: "Elixir GenServer patterns",
          body: "GenServers handle synchronous and asynchronous messages.",
          impression: "GenServer patterns for Elixir",
          recall: "GenServers use handle_call for sync and handle_cast for async.",
          tags: ["elixir", "otp"],
          source: "manual",
          category: "semantic"
        })

      context = Muse.gather_context("GenServer")
      assert context =~ "GenServer"
      assert context =~ "Relevant Memories"
    end

    test "respects source filters as tags" do
      {:ok, _} =
        ExCortex.Memory.create_engram(%{
          title: "Tagged memory",
          body: "This is tagged content.",
          impression: "Tagged content",
          tags: ["special"],
          source: "manual",
          category: "semantic"
        })

      # With matching filter
      context = Muse.gather_context("tagged", ["special"])
      assert context =~ "Tagged memory"
    end
  end

  describe "ask/2" do
    # Note: These tests require an LLM to be running. In CI, they would be
    # tagged @tag :integration and skipped. For local dev, they test the full flow.

    @tag :llm
    test "wonder scope creates a thought with no context" do
      {:ok, thought} = Muse.ask("What is 2+2?", scope: "wonder")
      assert thought.scope == "wonder"
      assert thought.status == "complete"
      assert thought.question == "What is 2+2?"
      assert is_binary(thought.answer)
    end

    @tag :llm
    test "muse scope creates a thought with context" do
      {:ok, thought} = Muse.ask("What do I know about Elixir?", scope: "muse")
      assert thought.scope == "muse"
      assert thought.status == "complete"
    end
  end
end
