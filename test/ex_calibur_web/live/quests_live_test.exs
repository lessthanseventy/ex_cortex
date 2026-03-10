defmodule ExCaliburWeb.QuestsLiveTest do
  use ExCaliburWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCalibur.Quests

  setup do
    {:ok, step} = Quests.create_step(%{name: "Test Step", trigger: "manual", roster: []})

    {:ok, quest} =
      Quests.create_quest(%{
        name: "Test Quest",
        trigger: "manual",
        steps: [%{"step_id" => step.id, "flow" => "always"}]
      })

    %{step: step, quest: quest}
  end

  describe "index" do
    test "renders quests page with quests", %{conn: conn, quest: quest} do
      {:ok, view, html} = live(conn, "/quests")
      html_snapshot(view)
      assert html =~ quest.name
    end

    test "shows Custom tab in Quest Templates", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/quests")
      assert html =~ "board_set_tab"
    end

    test "new quest form renders", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/quests")
      render_click(view, "board_set_tab", %{"tab" => "custom"})
      html_snapshot(view)
      html = render(view)
      assert html =~ "form"
    end
  end

  test "create_quest event adds a quest", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/quests")

    render_click(view, "board_set_tab", %{"tab" => "custom"})

    html =
      view
      |> form("form[phx-submit=\"create_quest\"]", %{
        "quest" => %{
          "name" => "New Quest",
          "trigger" => "manual"
        }
      })
      |> render_submit()

    assert html =~ "New Quest"
  end

  test "toggle_quest_status toggles active/paused", %{conn: conn, quest: quest} do
    {:ok, view, _html} = live(conn, "/quests")
    html = render_click(view, "toggle_quest_status", %{"id" => to_string(quest.id)})
    assert html =~ "Resume" or html =~ "Pause"
  end

  test "delete_quest removes quest", %{conn: conn, quest: quest} do
    {:ok, view, _html} = live(conn, "/quests")
    html = render_click(view, "delete_quest", %{"id" => to_string(quest.id)})
    refute html =~ "Test Quest"
  end

  describe "quest templates" do
    test "renders quest templates section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/quests")
      assert html =~ "Quest Templates"
      assert html =~ "Triage"
      assert html =~ "Reporting"
      assert html =~ "Generation"
      assert html =~ "Review"
      assert html =~ "Onboarding"
    end

    test "filters templates by category", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/quests")
      html = view |> element("button", "Triage") |> render_click()
      assert html =~ "Jira Ticket Triage"
      refute html =~ "Weekly Security Digest"
    end

    test "/quest-board redirects to /quests", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/quest-board")
      assert html =~ "Quest Templates"
    end

    test "can install a no-requirement template", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/quests")
      view |> element("button", "Generation") |> render_click()

      view
      |> element("[phx-value-id='incident_postmortem']", "Install")
      |> render_click()

      html =
        view
        |> element("[phx-click='board_install_template'][phx-value-id='incident_postmortem']")
        |> render_click()

      assert html =~ "Installed"
    end
  end
end
