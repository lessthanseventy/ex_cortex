defmodule ExCortex.BannerTagsTest do
  use ExUnit.Case, async: true

  describe "pathway lobes" do
    test "all pathways have a lobe tag" do
      for {_name, mod} <- ExCortex.Evaluator.pathways() do
        meta = mod.metadata()

        assert meta[:lobe] in [:frontal, :parietal, :limbic, :cerebellar, :temporal, :occipital],
               "#{meta.name} missing lobe tag"
      end
    end
  end
end
