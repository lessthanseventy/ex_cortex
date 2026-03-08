defmodule ExCellenceServerWeb.QuestsLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders quests page with charters", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/quests")
      assert html =~ "Quests"
      assert html =~ "Content Moderation"
      assert html =~ "Code Review"
      assert html =~ "Risk Assessment"
    end
  end
end
