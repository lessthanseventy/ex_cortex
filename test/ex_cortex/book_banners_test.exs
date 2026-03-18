defmodule ExCortex.BookBannersTest do
  use ExUnit.Case, async: true

  alias ExCortex.Senses.Reflex

  describe "reflex lobes" do
    test "all reflexes have a lobe tag" do
      for reflex <- Reflex.all() do
        assert reflex.lobe in [:frontal, :parietal, :limbic, :cerebellar, :temporal, :occipital, nil],
               "Reflex #{reflex.id} missing lobe tag"
      end
    end

    test "filter_by_lobe/1 returns matching and nil-lobe reflexes" do
      tech = Reflex.filter_by_lobe(:frontal)
      assert tech != []
      assert Enum.all?(tech, &(&1.lobe in [:frontal, nil]))
    end
  end
end
