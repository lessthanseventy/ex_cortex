defmodule ExCellenceServerWeb.GuildHallLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders guild hall with available guilds", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/guild-hall")
      assert html =~ "Guild Hall"
      assert html =~ "Content Moderation"
      assert html =~ "Code Review"
      assert html =~ "Risk Assessment"
      assert html =~ "Install Guild"
    end
  end
end
