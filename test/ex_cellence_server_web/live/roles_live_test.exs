defmodule ExCellenceServerWeb.RolesLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders roles page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/roles")
      assert html =~ "Roles"
      assert html =~ "New Role"
    end
  end
end
