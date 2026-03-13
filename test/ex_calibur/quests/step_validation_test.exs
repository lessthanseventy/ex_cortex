defmodule ExCalibur.Quests.StepValidationTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Quests.Step

  describe "loop_mode validation" do
    test "changeset accepts valid loop_mode values" do
      valid_modes = ["reflect", "sequential", "parallel", "dynamic"]

      Enum.each(valid_modes, fn mode ->
        changeset = Step.changeset(%Step{}, %{name: "Test Step", trigger: "manual", loop_mode: mode})
        assert changeset.valid?, "expected #{mode} to be valid, errors: #{inspect(changeset.errors)}"
      end)
    end

    test "changeset rejects invalid loop_mode values" do
      invalid_modes = ["invalid", "loop", "async", "sync", "plan"]

      Enum.each(invalid_modes, fn mode ->
        changeset = Step.changeset(%Step{}, %{name: "Test Step", trigger: "manual", loop_mode: mode})
        refute changeset.valid?
        assert {:loop_mode, {"must be reflect, sequential, parallel, or dynamic", _}} =
                 List.keyfind(changeset.errors, :loop_mode, 0)
      end)
    end

    test "changeset works without loop_mode (nil is allowed)" do
      changeset = Step.changeset(%Step{}, %{name: "Test Step", trigger: "manual"})
      assert changeset.valid?
    end
  end
end
