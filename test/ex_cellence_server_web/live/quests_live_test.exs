defmodule ExCellenceServerWeb.QuestsLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders quests page with pipeline builder", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/quests")
      assert html =~ "Quests"
      assert html =~ "Plan Quest"
    end
  end
end
