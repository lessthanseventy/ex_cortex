defmodule ExCortex.PraxisLobesTest do
  use ExUnit.Case, async: true

  alias ExCortex.Praxis

  describe "praxis template lobes" do
    test "all templates have a lobe tag" do
      for template <- Praxis.all() do
        assert template.lobe in [:frontal, :parietal, :limbic, :cerebellar, :temporal, :occipital],
               "Template #{template.id} missing lobe tag"
      end
    end

    test "filter_by_lobe/1 returns only matching templates" do
      frontal = Praxis.filter_by_lobe(:frontal)
      assert frontal != []
      assert Enum.all?(frontal, &(&1.lobe == :frontal))
    end
  end
end
