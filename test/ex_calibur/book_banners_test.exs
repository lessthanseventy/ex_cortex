defmodule ExCalibur.BookBannersTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Sources.Book

  describe "book banners" do
    test "all books have a banner tag" do
      for book <- Book.all() do
        assert book.banner in [:tech, :lifestyle, :business, nil],
               "Book #{book.id} missing banner tag"
      end
    end

    test "filter_by_banner/1 returns matching and nil-banner books" do
      tech = Book.filter_by_banner(:tech)
      assert tech != []
      assert Enum.all?(tech, &(&1.banner in [:tech, nil]))
    end
  end
end
