defmodule ExCortex.BookBannersTest do
  use ExUnit.Case, async: true

  alias ExCortex.Senses.Reflex

  describe "reflex banners" do
    test "all reflexes have a banner tag" do
      for reflex <- Reflex.all() do
        assert reflex.banner in [:tech, :lifestyle, :business, nil],
               "Reflex #{reflex.id} missing banner tag"
      end
    end

    test "filter_by_banner/1 returns matching and nil-banner reflexes" do
      tech = Reflex.filter_by_banner(:tech)
      assert tech != []
      assert Enum.all?(tech, &(&1.banner in [:tech, nil]))
    end
  end
end
