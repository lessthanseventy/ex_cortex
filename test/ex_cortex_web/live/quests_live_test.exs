defmodule ExCortexWeb.QuestsLiveTest do
  use ExCortexWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCortex.Thoughts

  setup do
    ExCortex.Settings.set_banner("tech")
    {:ok, step} = Thoughts.create_synapse(%{name: "Test Step", trigger: "manual", roster: []})

    {:ok, thought} =
      Thoughts.create_thought(%{
        name: "Test Thought",
        trigger: "manual",
        steps: [%{"step_id" => step.id, "flow" => "always"}]
      })

    %{step: step, thought: thought}
  end

  describe "index" do
    test "renders thoughts page with thoughts", %{conn: conn, thought: thought} do
      {:ok, view, html} = live(conn, "/quests")
      html_snapshot(view)
      assert html =~ thought.name
    end

    test "shows Custom tab in Thought Templates", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/quests")
      assert html =~ "board_set_tab"
    end

    test "new thought form renders", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/quests")
      render_click(view, "board_set_tab", %{"tab" => "custom"})
      html_snapshot(view)
      html = render(view)
      assert html =~ "form"
    end
  end

  test "create_quest event adds a thought", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/quests")

    render_click(view, "board_set_tab", %{"tab" => "custom"})

    html =
      view
      |> form("form[phx-submit=\"create_quest\"]", %{
        "thought" => %{
          "name" => "New Thought",
          "trigger" => "manual"
        }
      })
      |> render_submit()

    assert html =~ "New Thought"
  end

  test "toggle_quest_status toggles active/paused", %{conn: conn, thought: thought} do
    {:ok, view, _html} = live(conn, "/quests")
    html = render_click(view, "toggle_quest_status", %{"id" => to_string(thought.id)})
    assert html =~ "Resume" or html =~ "Pause"
  end

  test "delete_quest removes thought", %{conn: conn, thought: thought} do
    {:ok, view, _html} = live(conn, "/quests")
    html = render_click(view, "delete_quest", %{"id" => to_string(thought.id)})
    refute html =~ "Test Thought"
  end

  describe "banner filtering" do
    test "thought board filters templates by banner", %{conn: conn} do
      ExCortex.Settings.set_banner("lifestyle")
      {:ok, _view, html} = live(conn, "/quests")
      # Lifestyle templates should appear
      # Tech-only templates should not
      refute html =~ "Jira Ticket Triage"
    end

    test "redirects to town square when no banner set", %{conn: conn} do
      ExCortex.Repo.delete_all(ExCortex.Settings)
      {:error, {:live_redirect, %{to: "/town-square"}}} = live(conn, "/quests")
    end
  end

  describe "thought templates" do
    test "renders thought templates section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/quests")
      assert html =~ "Thought Templates"
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

    test "/thought-board redirects to /thoughts", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/thought-board")
      assert html =~ "Thought Templates"
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

  describe "thought card redesign" do
    test "thought template shows step count", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/quests")
      assert html =~ ~r/\d+ steps?/
    end

    test "expanding a template shows nested step cards", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/quests")

      html =
        view
        |> element(~s{[phx-click="board_expand_template"][phx-value-id="jira_ticket_triage"]})
        |> render_click()

      assert html =~ "step-card"
    end
  end
end
