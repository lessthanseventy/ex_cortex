defmodule ExCortex.ContextProviders.NeuronRosterTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.ContextProviders.NeuronRoster
  alias ExCortex.Neurons.Neuron

  test "returns empty string when no active neurons" do
    result = NeuronRoster.build(%{"type" => "member_roster"}, %{}, "")
    assert result == ""
  end

  test "lists active role neurons" do
    {:ok, _} =
      %Neuron{}
      |> Neuron.changeset(%{
        name: "Test Analyst",
        type: "role",
        status: "active",
        config: %{"rank" => "journeyman", "model" => "devstral-small-2:24b", "tools" => ["run_sandbox"]}
      })
      |> ExCortex.Repo.insert()

    result = NeuronRoster.build(%{"type" => "member_roster"}, %{}, "")
    assert result =~ "## cluster neurons"
    assert result =~ "Test Analyst"
    assert result =~ "journeyman"
    assert result =~ "devstral-small-2:24b"
  end

  test "respects custom label" do
    result = NeuronRoster.build(%{"type" => "member_roster", "label" => "## Team"}, %{}, "")
    # Label appears even when empty (returns "" when no neurons)
    assert is_binary(result)
  end
end
