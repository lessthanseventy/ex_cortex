defmodule ExCaliburWeb.TownSquareLiveTest do
  use ExCaliburWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders town square with category sections", %{conn: conn} do
      {:ok, view, html} = live(conn, "/town-square")
      html_snapshot(view)
      assert html =~ "Town Square"
      assert html =~ "Editors"
      assert html =~ "Analysts"
      assert html =~ "Specialists"
      assert html =~ "Advisors"
    end

    test "renders all members", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/town-square")

      for member <- ExCalibur.Members.BuiltinMember.all() do
        escaped = member.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        assert html =~ escaped
      end
    end

    test "shows rank buttons", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/town-square")
      assert html =~ "Apprentice"
      assert html =~ "Journeyman"
      assert html =~ "Master"
    end
  end
end
