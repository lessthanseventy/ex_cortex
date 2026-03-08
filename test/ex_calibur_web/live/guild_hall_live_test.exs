defmodule ExCaliburWeb.GuildHallLiveTest do
  use ExCaliburWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders guild hall with available guilds", %{conn: conn} do
      {:ok, view, html} = live(conn, "/guild-hall")
      html_snapshot(view)
      assert html =~ "Guild Hall"
      assert html =~ "Content Moderation"
      assert html =~ "Code Review"
      assert html =~ "Risk Assessment"
      assert html =~ "Install"
    end
  end
end
