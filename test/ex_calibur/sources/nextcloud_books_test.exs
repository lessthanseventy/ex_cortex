defmodule ExCalibur.Sources.NextcloudBooksTest do
  use ExUnit.Case, async: true

  alias ExCalibur.Sources.Book

  describe "nextcloud books" do
    test "includes nextcloud_files book" do
      books = Book.all()
      assert Enum.any?(books, &(&1.id == "nextcloud_files"))
    end

    test "includes nextcloud_notes book" do
      books = Book.all()
      assert Enum.any?(books, &(&1.id == "nextcloud_notes"))
    end

    test "includes nextcloud_calendar book" do
      books = Book.all()
      assert Enum.any?(books, &(&1.id == "nextcloud_calendar"))
    end

    test "includes nextcloud_talk book" do
      books = Book.all()
      assert Enum.any?(books, &(&1.id == "nextcloud_talk"))
    end

    test "all nextcloud books have source_type nextcloud" do
      nc_books = Enum.filter(Book.all(), &String.starts_with?(&1.id, "nextcloud_"))
      assert length(nc_books) == 4
      assert Enum.all?(nc_books, &(&1.source_type == "nextcloud"))
    end
  end
end
