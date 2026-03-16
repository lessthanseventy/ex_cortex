defmodule ExCortex.PraxisLobesTest do
  use ExUnit.Case, async: true

  alias ExCortex.Praxis

  describe "praxis template lobes" do
    test "all templates have a lobe tag" do
      for template <- Praxis.all() do
        assert template.lobe in [:tech, :lifestyle, :business],
               "Template #{template.id} missing lobe tag"
      end
    end

    test "filter_by_lobe/1 returns only matching templates" do
      tech = Praxis.filter_by_lobe(:tech)
      assert tech != []
      assert Enum.all?(tech, &(&1.lobe == :tech))
    end
  end
end
