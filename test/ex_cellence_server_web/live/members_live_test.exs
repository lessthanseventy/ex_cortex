defmodule ExCellenceServerWeb.MembersLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders members page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/members")
      assert html =~ "Members"
      assert html =~ "New Member"
    end
  end
end
