defmodule ExCaliburWeb.QuestBoardLiveTest do
  use ExCaliburWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders quest board with templates", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/quest-board")

    assert html =~ "Quest Board"
    assert html =~ "Triage"
    assert html =~ "Reporting"
    assert html =~ "Generation"
    assert html =~ "Review"
    assert html =~ "Onboarding"
  end

  test "shows category filter buttons", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/quest-board")
    assert html =~ "All"
    assert html =~ "Triage"
    assert html =~ "Onboarding"
  end

  test "filters by category", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/quest-board")

    html = view |> element("button", "Triage") |> render_click()
    assert html =~ "Jira Ticket Triage"
    refute html =~ "Weekly Security Digest"
  end

  test "shows unavailable templates when toggled", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/quest-board")

    # By default, unavailable templates may be hidden — click show all
    html = view |> element("button", "Show all") |> render_click()
    # After toggle, unavailable templates should appear
    assert html =~ "Jira Ticket Triage"
  end

  test "can install a no-requirement template", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/quest-board")

    # Filter to Generation to find incident_postmortem (no requirements)
    view |> element("button", "Generation") |> render_click()

    # Click Install on the Incident Postmortem template
    view
    |> element("[phx-value-id='incident_postmortem']", "Install")
    |> render_click()

    # Confirm the install
    html =
      view
      |> element("[phx-click='install_template'][phx-value-id='incident_postmortem']")
      |> render_click()

    assert html =~ "Installed"
  end
end
