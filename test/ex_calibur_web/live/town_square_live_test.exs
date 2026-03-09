defmodule ExCaliburWeb.TownSquareLiveTest do
  use ExCaliburWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders town square with available guilds", %{conn: conn} do
      {:ok, view, html} = live(conn, "/town-square")
      html_snapshot(view)
      assert html =~ "Town Square"
      assert html =~ "Content Moderation"
      assert html =~ "Code Review"
      assert html =~ "Risk Assessment"
      assert html =~ "Install"
    end
  end
end
