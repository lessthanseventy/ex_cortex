defmodule ExCortex.ThoughtsTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Thoughts

  test "create_thought/1 with valid params" do
    {:ok, thought} = Thoughts.create_thought(%{question: "What is the meaning of life?", scope: "wonder"})
    assert thought.question == "What is the meaning of life?"
    assert thought.scope == "wonder"
    assert thought.status == "draft"
  end

  test "create_thought/1 requires question" do
    {:error, changeset} = Thoughts.create_thought(%{scope: "muse"})
    assert %{question: _} = errors_on(changeset)
  end

  test "create_thought/1 validates scope" do
    {:error, changeset} = Thoughts.create_thought(%{question: "test", scope: "invalid"})
    assert %{scope: _} = errors_on(changeset)
  end

  test "list_thoughts/0 returns all thoughts" do
    {:ok, _} = Thoughts.create_thought(%{question: "q1", scope: "wonder"})
    {:ok, _} = Thoughts.create_thought(%{question: "q2", scope: "muse"})
    assert length(Thoughts.list_thoughts()) == 2
  end

  test "list_thoughts/1 filters by scope" do
    {:ok, _} = Thoughts.create_thought(%{question: "q1", scope: "wonder"})
    {:ok, _} = Thoughts.create_thought(%{question: "q2", scope: "muse"})
    assert length(Thoughts.list_thoughts(scope: "wonder")) == 1
  end

  test "list_thoughts/1 filters by status" do
    {:ok, _} = Thoughts.create_thought(%{question: "q1", scope: "muse", status: "complete"})
    {:ok, _} = Thoughts.create_thought(%{question: "q2", scope: "muse", status: "saved"})
    assert length(Thoughts.list_thoughts(status: "saved")) == 1
  end

  test "update_thought/2 updates a thought" do
    {:ok, thought} = Thoughts.create_thought(%{question: "q", scope: "muse"})
    {:ok, updated} = Thoughts.update_thought(thought, %{answer: "42", status: "complete"})
    assert updated.answer == "42"
    assert updated.status == "complete"
  end

  test "delete_thought/1 deletes a thought" do
    {:ok, thought} = Thoughts.create_thought(%{question: "q", scope: "wonder"})
    {:ok, _} = Thoughts.delete_thought(thought)
    assert Thoughts.list_thoughts() == []
  end

  test "save_to_memory/1 creates an engram from a thought" do
    {:ok, thought} =
      Thoughts.create_thought(%{
        question: "What happened today?",
        answer: "A lot of renaming.",
        scope: "muse",
        status: "complete",
        tags: ["daily"]
      })

    {:ok, engram} = Thoughts.save_to_memory(thought)
    assert engram.title == "What happened today?"
    assert engram.body == "A lot of renaming."
    assert engram.source == "muse"
    assert engram.category == "episodic"
  end
end
