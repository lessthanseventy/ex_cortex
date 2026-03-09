defmodule ExCaliburWeb.GrimoireLiveTest do
  use ExCaliburWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCalibur.Lore

  test "renders empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/grimoire")
    assert html =~ "Grimoire"
    assert html =~ "No entries yet"
  end

  test "renders existing entries", %{conn: conn} do
    {:ok, _} = Lore.create_entry(%{title: "My entry", body: "hello", tags: ["test"]})
    {:ok, view, html} = live(conn, "/grimoire")
    html_snapshot(view)
    assert html =~ "My entry"
    assert html =~ "test"
  end

  test "create entry manually", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/grimoire")
    render_click(view, "add_entry", %{})

    view
    |> form("form[phx-submit=\"create_entry\"]", %{
      "entry" => %{
        "title" => "Manual Entry",
        "body" => "Some content",
        "tags" => "a11y",
        "importance" => "3"
      }
    })
    |> render_submit()

    assert render(view) =~ "Manual Entry"
  end

  test "delete entry", %{conn: conn} do
    {:ok, entry} = Lore.create_entry(%{title: "To Delete"})
    {:ok, view, _html} = live(conn, "/grimoire")
    assert render(view) =~ "To Delete"
    render_click(view, "delete_entry", %{"id" => to_string(entry.id)})
    refute render(view) =~ "To Delete"
  end
end
