defmodule ExCortex.RuminationsTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Rumination
  alias ExCortex.Ruminations.Synapse

  describe "steps" do
    setup do
      ExCortex.Repo.delete_all(Synapse)
      :ok
    end

    test "list_steps returns all steps" do
      {:ok, _} = Ruminations.create_synapse(%{name: "Test Step", trigger: "manual"})
      assert [%Synapse{}] = Ruminations.list_synapses()
    end

    test "create_step with valid params" do
      assert {:ok, %Synapse{name: "My Step"}} =
               Ruminations.create_synapse(%{name: "My Step", trigger: "manual"})
    end

    test "create_step with invalid params" do
      assert {:error, %Ecto.Changeset{}} = Ruminations.create_synapse(%{})
    end

    test "update_step changes fields" do
      {:ok, step} = Ruminations.create_synapse(%{name: "Step A", trigger: "manual"})
      assert {:ok, %Synapse{status: "paused"}} = Ruminations.update_synapse(step, %{status: "paused"})
    end

    test "delete_step removes it" do
      {:ok, step} = Ruminations.create_synapse(%{name: "Step B", trigger: "manual"})
      assert {:ok, _} = Ruminations.delete_synapse(step)
      assert Ruminations.list_synapses() == []
    end
  end

  describe "ruminations" do
    setup do
      ExCortex.Repo.delete_all(Rumination)
      :ok
    end

    test "list_ruminations returns all thoughts" do
      {:ok, _} = Ruminations.create_rumination(%{name: "Rumination A", trigger: "manual"})
      assert [%Rumination{}] = Ruminations.list_ruminations()
    end

    test "create_rumination with valid params" do
      assert {:ok, %Rumination{name: "My Rumination"}} =
               Ruminations.create_rumination(%{name: "My Rumination", trigger: "manual"})
    end

    test "list_ruminations_for_source returns active source-triggered thoughts" do
      {:ok, q1} =
        Ruminations.create_rumination(%{
          name: "Rumination Source",
          trigger: "source",
          source_ids: ["src-abc"],
          status: "active"
        })

      # Paused rumination — should NOT appear
      {:ok, _q2} =
        Ruminations.create_rumination(%{
          name: "Paused Rumination",
          trigger: "source",
          source_ids: ["src-abc"],
          status: "paused"
        })

      # Different source — should NOT appear
      {:ok, _q3} =
        Ruminations.create_rumination(%{
          name: "Other Rumination",
          trigger: "source",
          source_ids: ["src-xyz"],
          status: "active"
        })

      assert [%Rumination{id: id}] = Ruminations.list_ruminations_for_source("src-abc")
      assert id == q1.id
    end
  end
end
