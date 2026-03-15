defmodule ExCortexWeb.GuideLiveTest do
  use ExCortexWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders guide page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/guide")
    assert html =~ "Guide"
    assert html =~ "Rumination"
    assert html =~ "Branch"
    assert html =~ "Challenger"
    assert html =~ "Trust"
  end
end
