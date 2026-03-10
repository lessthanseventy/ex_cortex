defmodule ExCaliburWeb.GuideLiveTest do
  use ExCaliburWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders guide page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/guide")
    assert html =~ "Guide"
    assert html =~ "Campaign"
    assert html =~ "Branch"
    assert html =~ "Challenger"
    assert html =~ "Trust"
  end
end
