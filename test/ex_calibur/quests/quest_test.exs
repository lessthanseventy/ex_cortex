defmodule ExCalibur.Quests.QuestTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Quests.Quest

  test "changeset valid with required fields" do
    params = %{name: "Monthly Audit", trigger: "manual", steps: []}
    assert %{valid?: true} = Quest.changeset(%Quest{}, params)
  end

  test "changeset invalid without name" do
    assert %{valid?: false} = Quest.changeset(%Quest{}, %{trigger: "manual"})
  end

  test "changeset valid with only name (trigger defaults to manual)" do
    assert %{valid?: true} = Quest.changeset(%Quest{}, %{name: "Monthly Audit"})
  end
end
