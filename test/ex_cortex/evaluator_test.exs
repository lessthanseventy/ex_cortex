defmodule ExCortex.EvaluatorTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Evaluator

  describe "pathways/0" do
    test "returns a non-empty map of pathway names to modules" do
      pathways = Evaluator.pathways()
      assert is_map(pathways)
      assert map_size(pathways) > 0
      assert Map.has_key?(pathways, "Dev Team")
    end

    test "all pathway values are valid modules" do
      Evaluator.pathways()
      |> Map.values()
      |> Enum.each(fn mod ->
        assert Code.ensure_loaded?(mod), "#{inspect(mod)} is not a loadable module"
      end)
    end
  end

  describe "evaluate/2" do
    test "returns error when no cluster is installed" do
      assert {:error, :no_guild_installed} = Evaluator.evaluate("some input text")
    end
  end
end
