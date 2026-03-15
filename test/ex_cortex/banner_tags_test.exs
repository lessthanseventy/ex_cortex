defmodule ExCortex.BannerTagsTest do
  use ExUnit.Case, async: true

  describe "pathway banners" do
    test "all pathways have a banner tag" do
      for {_name, mod} <- ExCortex.Evaluator.pathways() do
        meta = mod.metadata()

        assert meta[:banner] in [:tech, :lifestyle, :business],
               "#{meta.name} missing banner tag"
      end
    end
  end
end
