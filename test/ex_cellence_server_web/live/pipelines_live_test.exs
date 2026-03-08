defmodule ExCellenceServerWeb.PipelinesLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders pipelines page with templates", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/pipelines")
      assert html =~ "Pipelines"
      assert html =~ "Content Moderation"
      assert html =~ "Code Review"
      assert html =~ "Risk Assessment"
    end
  end
end
