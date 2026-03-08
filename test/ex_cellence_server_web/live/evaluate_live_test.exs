defmodule ExCellenceServerWeb.EvaluateLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders evaluate page with input form", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/evaluate")
      assert html =~ "Evaluate"
      assert html =~ "Run"
    end
  end
end
