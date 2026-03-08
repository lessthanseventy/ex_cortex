defmodule ExCellenceServerWeb.LibraryLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders library with available books", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/library")
      assert html =~ "Library"
      assert html =~ "Git Repo Watcher"
      assert html =~ "RSS/Atom Feed"
      assert html =~ "Directory Watcher"
      assert html =~ "Webhook Receiver"
      assert html =~ "URL Watcher"
      assert html =~ "WebSocket Stream"
    end
  end
end
