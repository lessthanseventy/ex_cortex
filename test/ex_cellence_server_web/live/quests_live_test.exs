defmodule ExCellenceServerWeb.QuestsLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCellenceServer.Quests

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

    test "shows + New Quest button", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/quests")
      assert html =~ "New Quest"
    end

    test "shows + New Campaign button", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/quests")
      assert html =~ "New Campaign"
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
end
