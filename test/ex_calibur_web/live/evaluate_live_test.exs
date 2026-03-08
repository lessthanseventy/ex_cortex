defmodule ExCaliburWeb.EvaluateLiveTest do
  use ExCaliburWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "redirects /evaluate to /quests", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/quests"}}} = live(conn, "/evaluate")
    end
  end
end
