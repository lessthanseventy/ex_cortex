defmodule ExCortex.ThoughtsTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Thoughts
  alias ExCortex.Thoughts.Synapse
  alias ExCortex.Thoughts.Thought

  describe "steps" do
    setup do
      ExCortex.Repo.delete_all(Synapse)
      :ok
    end

    test "list_steps returns all steps" do
      {:ok, _} = Thoughts.create_synapse(%{name: "Test Step", trigger: "manual"})
      assert [%Synapse{}] = Thoughts.list_synapses()
    end

    test "create_step with valid params" do
      assert {:ok, %Synapse{name: "My Step"}} =
               Thoughts.create_synapse(%{name: "My Step", trigger: "manual"})
    end

    test "create_step with invalid params" do
      assert {:error, %Ecto.Changeset{}} = Thoughts.create_synapse(%{})
    end

    test "update_step changes fields" do
      {:ok, step} = Thoughts.create_synapse(%{name: "Step A", trigger: "manual"})
      assert {:ok, %Synapse{status: "paused"}} = Thoughts.update_synapse(step, %{status: "paused"})
    end

    test "delete_step removes it" do
      {:ok, step} = Thoughts.create_synapse(%{name: "Step B", trigger: "manual"})
      assert {:ok, _} = Thoughts.delete_synapse(step)
      assert Thoughts.list_synapses() == []
    end
  end

  describe "thoughts" do
    setup do
      ExCortex.Repo.delete_all(Thought)
      :ok
    end

    test "list_thoughts returns all thoughts" do
      {:ok, _} = Thoughts.create_thought(%{name: "Thought A", trigger: "manual"})
      assert [%Thought{}] = Thoughts.list_thoughts()
    end

    test "create_thought with valid params" do
      assert {:ok, %Thought{name: "My Thought"}} =
               Thoughts.create_thought(%{name: "My Thought", trigger: "manual"})
    end

    test "list_thoughts_for_source returns active source-triggered thoughts" do
      {:ok, q1} =
        Thoughts.create_thought(%{
          name: "Thought Source",
          trigger: "source",
          source_ids: ["src-abc"],
          status: "active"
        })

      # Paused thought — should NOT appear
      {:ok, _q2} =
        Thoughts.create_thought(%{
          name: "Paused Thought",
          trigger: "source",
          source_ids: ["src-abc"],
          status: "paused"
        })

      # Different source — should NOT appear
      {:ok, _q3} =
        Thoughts.create_thought(%{
          name: "Other Thought",
          trigger: "source",
          source_ids: ["src-xyz"],
          status: "active"
        })

      assert [%Thought{id: id}] = Thoughts.list_thoughts_for_source("src-abc")
      assert id == q1.id
    end
  end
end
