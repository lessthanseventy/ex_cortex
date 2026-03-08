defmodule ExCellenceServerWeb.DashboardLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders dashboard with component sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")
      assert html =~ "Dashboard"
      assert html =~ "Recent Decisions"
      assert html =~ "Agent Health"
    end
  end
end
