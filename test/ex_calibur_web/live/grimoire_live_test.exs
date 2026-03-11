defmodule ExCaliburWeb.GrimoireLiveTest do
  use ExCaliburWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCalibur.Quests

  setup do
    ExCalibur.Settings.set_banner("tech")
    :ok
  end

  test "renders quest log with empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/grimoire")
    assert html =~ "Grimoire"
    assert html =~ "No quests yet"
  end

  test "renders quest cards when quests exist", %{conn: conn} do
    {:ok, step} = Quests.create_step(%{name: "Test Step", trigger: "manual", roster: []})

    {:ok, _quest} =
      Quests.create_quest(%{
        name: "My Quest",
        trigger: "manual",
        steps: [%{"step_id" => step.id, "flow" => "always"}]
      })

    {:ok, view, html} = live(conn, "/grimoire")
    html_snapshot(view)
    assert html =~ "My Quest"
    assert html =~ "active"
    assert html =~ "manual"
  end

  test "shows run stats for quests with runs", %{conn: conn} do
    {:ok, step} = Quests.create_step(%{name: "Stats Step", trigger: "manual", roster: []})

    {:ok, quest} =
      Quests.create_quest(%{
        name: "Stats Quest",
        trigger: "manual",
        steps: [%{"step_id" => step.id, "flow" => "always"}]
      })

    {:ok, _run} = Quests.create_quest_run(%{quest_id: quest.id, status: "complete"})
    {:ok, _run2} = Quests.create_quest_run(%{quest_id: quest.id, status: "failed"})

    {:ok, _view, html} = live(conn, "/grimoire")
    assert html =~ "Runs: 2"
    assert html =~ "1 ok"
    assert html =~ "1 failed"
  end

  test "shows quest log and telemetry tabs", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/grimoire")
    assert html =~ "Quest Log"
    assert html =~ "Telemetry"
  end

  test "redirects to town square when no banner set", %{conn: conn} do
    ExCalibur.Repo.delete_all(ExCalibur.Settings)
    {:error, {:live_redirect, %{to: "/town-square"}}} = live(conn, ~p"/grimoire")
  end

  test "shows paused badge for paused quests", %{conn: conn} do
    {:ok, step} = Quests.create_step(%{name: "Paused Step", trigger: "manual", roster: []})

    {:ok, _quest} =
      Quests.create_quest(%{
        name: "Paused Quest",
        trigger: "manual",
        status: "paused",
        steps: [%{"step_id" => step.id, "flow" => "always"}]
      })

    {:ok, _view, html} = live(conn, "/grimoire")
    assert html =~ "Paused Quest"
    assert html =~ "paused"
  end
end
