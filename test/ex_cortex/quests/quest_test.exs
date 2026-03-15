defmodule ExCortex.Ruminations.RuminationTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Ruminations.Rumination

  test "changeset valid with required fields" do
    params = %{name: "Monthly Audit", trigger: "manual", steps: []}
    assert %{valid?: true} = Rumination.changeset(%Rumination{}, params)
  end

  test "changeset invalid without name" do
    assert %{valid?: false} = Rumination.changeset(%Rumination{}, %{trigger: "manual"})
  end

  test "changeset valid with only name (trigger defaults to manual)" do
    assert %{valid?: true} = Rumination.changeset(%Rumination{}, %{name: "Monthly Audit"})
  end
end
