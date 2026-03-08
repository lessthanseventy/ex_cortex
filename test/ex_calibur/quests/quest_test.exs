defmodule ExCalibur.Quests.QuestTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Quests.Quest

  test "changeset valid with required fields" do
    params = %{name: "WCAG Scan", trigger: "manual", roster: []}
    assert %{valid?: true} = Quest.changeset(%Quest{}, params)
  end

  test "changeset invalid without name" do
    assert %{valid?: false} = Quest.changeset(%Quest{}, %{trigger: "manual"})
  end

  test "changeset invalid without trigger" do
    assert %{valid?: false} = Quest.changeset(%Quest{}, %{name: "WCAG Scan"})
  end
end
