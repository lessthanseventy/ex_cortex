defmodule ExCortex.MemberTeamTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Neurons.Neuron

  test "team can be set on a neuron changeset" do
    attrs = %{
      type: "role",
      name: "test-neuron",
      source: "db",
      status: "active",
      team: "alpha"
    }

    changeset = Neuron.changeset(%Neuron{}, attrs)
    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :team) == "alpha"
  end

  test "team defaults to nil when not provided" do
    attrs = %{type: "role", name: "test-neuron", source: "db"}
    changeset = Neuron.changeset(%Neuron{}, attrs)
    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :team) == nil
  end

  test "team is persisted to the database" do
    attrs = %{
      type: "role",
      name: "team-neuron",
      source: "db",
      status: "active",
      team: "bravo"
    }

    {:ok, neuron} =
      %Neuron{}
      |> Neuron.changeset(attrs)
      |> ExCortex.Repo.insert()

    assert neuron.team == "bravo"

    fetched = ExCortex.Repo.get!(Neuron, neuron.id)
    assert fetched.team == "bravo"
  end
end
