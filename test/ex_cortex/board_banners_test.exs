defmodule ExCortex.BoardBannersTest do
  use ExUnit.Case, async: true

  alias ExCortex.Board

  describe "board template banners" do
    test "all templates have a banner tag" do
      for template <- Board.all() do
        assert template.banner in [:tech, :lifestyle, :business],
               "Template #{template.id} missing banner tag"
      end
    end

    test "filter_by_banner/1 returns only matching templates" do
      tech = Board.filter_by_banner(:tech)
      assert tech != []
      assert Enum.all?(tech, &(&1.banner == :tech))
    end
  end
end
