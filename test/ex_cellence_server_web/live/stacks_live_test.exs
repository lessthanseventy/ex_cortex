defmodule ExCellenceServerWeb.StacksLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders stacks page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/stacks")
      assert html =~ "Stacks"
      assert html =~ "Browse Library"
    end

    test "shows empty state message", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/stacks")
      assert html =~ "Your stacks are empty"
    end
  end
end
