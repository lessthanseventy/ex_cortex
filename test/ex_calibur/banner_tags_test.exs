defmodule ExCalibur.BannerTagsTest do
  use ExUnit.Case, async: true

  describe "charter banners" do
    test "all charters have a banner tag" do
      for {_name, mod} <- ExCaliburWeb.TownSquareLive.charters() do
        meta = mod.metadata()

        assert meta[:banner] in [:tech, :lifestyle, :business],
               "#{meta.name} missing banner tag"
      end
    end
  end
end
