defmodule ExCaliburWeb.LodgeLiveTest do
  use ExCaliburWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCalibur.Lodge
  alias Excellence.Schemas.Member

  defp insert_member do
    %Member{}
    |> Member.changeset(%{type: "role", name: "Test Role", status: "active", source: "db", config: %{}})
    |> ExCalibur.Repo.insert!()
  end

  describe "index" do
    setup do
      ExCalibur.Repo.delete_all(Member)
      ExCalibur.Settings.set_banner("tech")
      :ok
    end

    test "redirects to town square when no members exist", %{conn: conn} do
      {:error, {:live_redirect, %{to: "/town-square"}}} = live(conn, "/lodge")
    end

    test "redirects to town square when no banner set", %{conn: conn} do
      insert_member()
      ExCalibur.Repo.delete_all(ExCalibur.Settings)
      assert ExCalibur.Settings.get_banner() == nil
      {:error, {:live_redirect, %{to: "/town-square"}}} = live(conn, ~p"/lodge")
    end
  end

  describe "card workspace" do
    setup do
      ExCalibur.Repo.delete_all(Member)
      ExCalibur.Settings.set_banner("tech")
      :ok
    end

    test "shows empty state when no cards exist", %{conn: conn} do
      insert_member()
      {:ok, view, html} = live(conn, "/lodge")
      html_snapshot(view)
      assert html =~ "Lodge"
      assert html =~ "No cards yet"
    end

    test "shows cards", %{conn: conn} do
      insert_member()
      Lodge.create_card(%{type: "note", title: "Hello World", body: "test", source: "manual"})
      {:ok, _view, html} = live(conn, "/lodge")
      assert html =~ "Hello World"
    end

    test "can create a note card", %{conn: conn} do
      insert_member()
      {:ok, view, _html} = live(conn, "/lodge")

      view
      |> form("form[phx-submit=create_card]", %{
        "card" => %{"type" => "note", "title" => "New Note", "body" => "content"}
      })
      |> render_submit()

      assert render(view) =~ "New Note"
    end

    test "can dismiss a card", %{conn: conn} do
      insert_member()
      {:ok, card} = Lodge.create_card(%{type: "note", title: "Dismiss Me", source: "manual"})
      {:ok, view, _html} = live(conn, "/lodge")
      assert render(view) =~ "Dismiss Me"

      render_click(view, "dismiss_card", %{"card-id" => to_string(card.id)})
      refute render(view) =~ "Dismiss Me"
    end

    test "displays augury card synced from lore", %{conn: conn} do
      insert_member()

      ExCalibur.Lore.create_entry(%{
        title: "World Thesis",
        body: "Markets are shifting",
        tags: ["augury"],
        source: "manual"
      })

      {:ok, _view, html} = live(conn, "/lodge")
      assert html =~ "The Augury"
      assert html =~ "World Thesis"
    end

    test "can toggle pin", %{conn: conn} do
      insert_member()
      {:ok, card} = Lodge.create_card(%{type: "note", title: "Pin Me", source: "manual"})
      {:ok, view, _html} = live(conn, "/lodge")

      render_click(view, "toggle_pin", %{"card-id" => to_string(card.id)})
      html = render(view)
      assert html =~ "pinned" or html =~ "Unpin"
    end
  end
end
