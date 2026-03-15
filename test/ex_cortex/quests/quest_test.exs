defmodule ExCortex.Thoughts.QuestTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Thoughts.Thought

  test "changeset valid with required fields" do
    params = %{name: "Monthly Audit", trigger: "manual", steps: []}
    assert %{valid?: true} = Thought.changeset(%Thought{}, params)
  end

  test "changeset invalid without name" do
    assert %{valid?: false} = Thought.changeset(%Thought{}, %{trigger: "manual"})
  end

  test "changeset valid with only name (trigger defaults to manual)" do
    assert %{valid?: true} = Thought.changeset(%Thought{}, %{name: "Monthly Audit"})
  end
end
