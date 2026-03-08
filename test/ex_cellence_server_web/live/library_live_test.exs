defmodule ExCellenceServerWeb.LibraryLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  use Excessibility

  alias ExCellenceServer.Sources.Book

  describe "index" do
    test "renders library with scrolls and books sections", %{conn: conn} do
      {:ok, view, html} = live(conn, "/library")
      html_snapshot(view)
      assert html =~ "Library"
      assert html =~ "Scrolls"
      assert html =~ "Books"
    end

    test "renders all books", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/library")

      for book <- Book.books() do
        escaped = book.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        assert html =~ escaped
      end
    end

    test "renders all scrolls", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/library")

      for scroll <- Book.scrolls() do
        escaped = scroll.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        assert html =~ escaped
      end
    end

    test "shows add to stacks button", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/library")
      assert html =~ "Add to Stacks"
    end
  end
end
