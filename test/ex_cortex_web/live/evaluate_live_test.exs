defmodule ExCortexWeb.EvaluateLiveTest do
  use ExCortexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "redirects /evaluate to /thoughts", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/thoughts"}}} = live(conn, "/evaluate")
    end
  end
end
