defmodule ExCaliburWeb.SettingsLiveTest do
  use ExCaliburWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    ExCalibur.Settings.set_banner("tech")
    :ok
  end

  test "renders settings page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings")
    assert html =~ "Settings"
    assert html =~ "Obsidian"
    assert html =~ "Vision"
  end

  test "saves a setting", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    view
    |> form("form:has(input[value='github'])", %{
      "settings" => %{"default_repo" => "myorg/myrepo"}
    })
    |> render_submit()

    assert ExCalibur.Settings.get(:default_repo) == "myorg/myrepo"
  end
end
