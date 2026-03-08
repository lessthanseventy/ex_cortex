defmodule ExCaliburWeb.LodgeLiveTest do
  use ExCaliburWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias Excellence.Schemas.Member
  alias ExCalibur.Quests

  defp insert_member do
    %Member{}
    |> Member.changeset(%{type: "role", name: "Test Role", status: "active", source: "db", config: %{}})
    |> ExCalibur.Repo.insert!()
  end

  describe "index" do
    test "redirects to guild hall when no members exist", %{conn: conn} do
      {:error, {:live_redirect, %{to: "/guild-hall"}}} = live(conn, "/lodge")
    end

    test "renders lodge with component sections when members exist", %{conn: conn} do
      insert_member()

      {:ok, view, html} = live(conn, "/lodge")
      html_snapshot(view)
      assert html =~ "Lodge"
      assert html =~ "Recent Decisions"
      assert html =~ "Agent Health"
      assert html =~ "Proposals"
    end

    test "shows empty proposals state when no proposals exist", %{conn: conn} do
      insert_member()

      {:ok, _view, html} = live(conn, "/lodge")
      assert html =~ "No pending proposals"
    end

    test "shows pending proposal with approve and reject buttons", %{conn: conn} do
      insert_member()

      {:ok, quest} =
        Quests.create_quest(%{name: "Auto Quest", trigger: "scheduled", roster: [], schedule: "0 * * * *"})

      {:ok, quest_run} = Quests.create_quest_run(%{quest_id: quest.id, input: "test input", status: "complete"})

      Quests.create_proposal(%{
        quest_id: quest.id,
        quest_run_id: quest_run.id,
        type: "roster_change",
        description: "Switch to master tier only",
        details: %{"suggestion" => "Narrow roster to master members"},
        status: "pending"
      })

      {:ok, _view, html} = live(conn, "/lodge")
      assert html =~ "Switch to master tier only"
      assert html =~ "roster_change"
      assert html =~ "Approve"
      assert html =~ "Reject"
    end

    test "approve_proposal marks proposal approved and removes from list", %{conn: conn} do
      insert_member()

      {:ok, quest} =
        Quests.create_quest(%{name: "Auto Quest", trigger: "scheduled", roster: [], schedule: "0 * * * *"})

      {:ok, _quest_run} = Quests.create_quest_run(%{quest_id: quest.id, input: "test input", status: "complete"})

      {:ok, proposal} =
        Quests.create_proposal(%{
          quest_id: quest.id,
          type: "prompt_change",
          description: "Tighten the system prompt",
          status: "pending"
        })

      {:ok, view, _html} = live(conn, "/lodge")
      html = render_click(view, "approve_proposal", %{"id" => to_string(proposal.id)})
      refute html =~ "Tighten the system prompt"
    end

    test "reject_proposal removes proposal from list", %{conn: conn} do
      insert_member()

      {:ok, quest} =
        Quests.create_quest(%{name: "Auto Quest", trigger: "scheduled", roster: [], schedule: "0 * * * *"})

      {:ok, proposal} =
        Quests.create_proposal(%{
          quest_id: quest.id,
          type: "schedule_change",
          description: "Run less frequently",
          status: "pending"
        })

      {:ok, view, _html} = live(conn, "/lodge")
      html = render_click(view, "reject_proposal", %{"id" => to_string(proposal.id)})
      refute html =~ "Run less frequently"
    end
  end
end
