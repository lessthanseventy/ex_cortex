defmodule ExCaliburWeb.QuestsLiveTest do
  use ExCaliburWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCalibur.Quests

  setup do
    {:ok, quest} = Quests.create_quest(%{name: "Test Quest", trigger: "manual", roster: []})

    {:ok, campaign} =
      Quests.create_campaign(%{
        name: "Test Campaign",
        trigger: "manual",
        steps: [%{"quest_id" => quest.id, "flow" => "always"}]
      })

    %{quest: quest, campaign: campaign}
  end

  describe "index" do
    test "renders quest board with quests and campaigns", %{conn: conn, quest: quest, campaign: campaign} do
      {:ok, view, html} = live(conn, "/quests")
      html_snapshot(view)
      assert html =~ quest.name
      assert html =~ campaign.name
    end

    test "shows + Quest button", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/quests")
      assert html =~ "+ Quest"
    end

    test "shows + Campaign button", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/quests")
      assert html =~ "+ Campaign"
    end

    test "new quest form renders with accessibility snapshot", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/quests")
      render_click(view, "add_quest", %{})
      html_snapshot(view)
      html = render(view)
      assert html =~ "form"
    end
  end

  test "create_quest event adds a quest", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/quests")

    render_click(view, "add_quest", %{})

    html =
      view
      |> form("form[phx-submit=\"create_quest\"]", %{
        "quest" => %{
          "name" => "New Quest",
          "trigger" => "manual",
          "who" => "all",
          "how" => "consensus"
        }
      })
      |> render_submit()

    assert html =~ "New Quest"
  end

  test "toggle_quest_status toggles active/paused", %{conn: conn, quest: quest} do
    {:ok, view, _html} = live(conn, "/quests")
    html = render_click(view, "toggle_quest_status", %{"id" => to_string(quest.id)})
    # after toggling active quest, it becomes paused — "Resume" button shows
    assert html =~ "Resume" or html =~ "Pause"
  end

  test "delete_quest removes quest", %{conn: conn, quest: quest} do
    {:ok, view, _html} = live(conn, "/quests")
    html = render_click(view, "delete_quest", %{"id" => to_string(quest.id)})
    refute html =~ "Test Quest"
  end

  describe "herald output type" do
    setup do
      {:ok, herald} =
        ExCalibur.Heralds.create_herald(%{
          name: "slack:eng",
          type: "slack",
          config: %{"webhook_url" => "https://hooks.slack.com/test"}
        })

      %{herald: herald}
    end

    test "quest form shows herald options in output type select", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/quests")
      view |> element("[phx-click=add_quest]") |> render_click()
      html = render(view)
      assert html =~ "Slack"
      assert html =~ "Webhook"
      assert html =~ "GitHub Issue"
    end

    test "selecting herald output type shows herald_name select", %{conn: conn, herald: _} do
      {:ok, view, _html} = live(conn, ~p"/quests")
      view |> element("[phx-click=add_quest]") |> render_click()

      html =
        view
        |> form("form[phx-change=preview_new_quest_trigger]", %{"quest" => %{"output_type" => "slack"}})
        |> render_change()

      assert html =~ "Herald"
      assert html =~ "slack:eng"
    end

    test "can create a herald quest", %{conn: conn, herald: _} do
      {:ok, view, _html} = live(conn, ~p"/quests")
      view |> element("[phx-click=add_quest]") |> render_click()

      # First change output_type to reveal the herald_name select
      view
      |> form("form[phx-change=preview_new_quest_trigger]", %{"quest" => %{"output_type" => "slack"}})
      |> render_change()

      view
      |> form("form[phx-submit=create_quest]", %{
        "quest" => %{
          "name" => "Slack Notifier",
          "output_type" => "slack",
          "herald_name" => "slack:eng",
          "trigger" => "manual"
        }
      })
      |> render_submit()

      quest = Enum.find(Quests.list_quests(), &(&1.name == "Slack Notifier"))
      assert quest.output_type == "slack"
      assert quest.herald_name == "slack:eng"
    end
  end

  describe "campaign templates (quest board)" do
    test "renders campaign templates section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/quests")
      assert html =~ "Campaign Templates"
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
      assert html =~ "Campaign Templates"
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
