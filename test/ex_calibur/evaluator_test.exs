defmodule ExCalibur.EvaluatorTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Evaluator

  describe "charters/0" do
    test "returns a non-empty map of charter names to modules" do
      charters = Evaluator.charters()
      assert is_map(charters)
      assert map_size(charters) > 0
      assert Map.has_key?(charters, "Dev Team")
    end

    test "all charter values are valid modules" do
      Evaluator.charters()
      |> Map.values()
      |> Enum.each(fn mod ->
        assert Code.ensure_loaded?(mod), "#{inspect(mod)} is not a loadable module"
      end)
    end
  end

  describe "evaluate/2" do
    test "returns error when no guild is installed" do
      assert {:error, :no_guild_installed} = Evaluator.evaluate("some input text")
    end
  end
end
