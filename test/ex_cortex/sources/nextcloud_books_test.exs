defmodule ExCortex.Senses.NextcloudBooksTest do
  use ExUnit.Case, async: true

  alias ExCortex.Senses.Reflex

  describe "nextcloud reflexes" do
    test "includes nextcloud_files reflex" do
      reflexes = Reflex.all()
      assert Enum.any?(reflexes, &(&1.id == "nextcloud_files"))
    end

    test "includes nextcloud_notes reflex" do
      reflexes = Reflex.all()
      assert Enum.any?(reflexes, &(&1.id == "nextcloud_notes"))
    end

    test "includes nextcloud_calendar reflex" do
      reflexes = Reflex.all()
      assert Enum.any?(reflexes, &(&1.id == "nextcloud_calendar"))
    end

    test "includes nextcloud_talk reflex" do
      reflexes = Reflex.all()
      assert Enum.any?(reflexes, &(&1.id == "nextcloud_talk"))
    end

    test "all nextcloud reflexes have source_type nextcloud" do
      nc_books = Enum.filter(Reflex.all(), &String.starts_with?(&1.id, "nextcloud_"))
      assert length(nc_books) == 4
      assert Enum.all?(nc_books, &(&1.source_type == "nextcloud"))
    end
  end
end
