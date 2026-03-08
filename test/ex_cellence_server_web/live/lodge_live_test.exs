defmodule ExCellenceServerWeb.LodgeLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Excellence.Schemas.ResourceDefinition

  describe "index" do
    test "redirects to guild hall when no members exist", %{conn: conn} do
      {:error, {:live_redirect, %{to: "/guild-hall"}}} = live(conn, "/lodge")
    end

    test "renders lodge with component sections when members exist", %{conn: conn} do
      %ResourceDefinition{}
      |> ResourceDefinition.changeset(%{type: "role", name: "Test Role", status: "active", source: "db", config: %{}})
      |> ExCellenceServer.Repo.insert!()

      {:ok, _view, html} = live(conn, "/lodge")
      assert html =~ "Lodge"
      assert html =~ "Recent Decisions"
      assert html =~ "Agent Health"
    end
  end
end
