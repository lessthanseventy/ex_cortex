defmodule ExCortexWeb.TownSquareLiveTest do
  use ExCortexWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders town square with available clusters", %{conn: conn} do
      ExCortex.Settings.set_banner("tech")
      {:ok, view, html} = live(conn, "/town-square")
      html_snapshot(view)
      assert html =~ "Town Square"
      assert html =~ "Code Review"
      assert html =~ "Install"
    end
  end

  describe "banner selection" do
    test "shows banner picker when no banner set", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/town-square")
      assert html =~ "Choose Your Banner"
      assert html =~ "tech"
      assert html =~ "lifestyle"
      assert html =~ "business"
    end

    test "selecting a banner filters clusters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/town-square")

      html =
        view |> element(~s{[phx-click="select_banner"][phx-value-banner="tech"]}) |> render_click()

      # Should show tech clusters, not lifestyle ones
      assert html =~ "Code Review"
      refute html =~ "Everyday Council"
    end

    test "banner persists to settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/town-square")
      view |> element(~s{[phx-click="select_banner"][phx-value-banner="tech"]}) |> render_click()
      assert ExCortex.Settings.get_banner() == "tech"
    end

    test "nav shows banner indicator when banner is set", %{conn: conn} do
      ExCortex.Settings.set_banner("tech")
      {:ok, _view, html} = live(conn, ~p"/town-square")
      assert html =~ "tech"
    end
  end
end
