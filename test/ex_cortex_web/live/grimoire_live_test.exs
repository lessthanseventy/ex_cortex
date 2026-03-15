defmodule ExCortexWeb.GrimoireLiveTest do
  use ExCortexWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCortex.Thoughts

  setup do
    ExCortex.Settings.set_banner("tech")
    :ok
  end

  test "renders thought log with empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/grimoire")
    assert html =~ "Grimoire"
    assert html =~ "No thoughts yet"
  end

  test "renders thought cards when thoughts exist", %{conn: conn} do
    {:ok, step} = Thoughts.create_synapse(%{name: "Test Step", trigger: "manual", roster: []})

    {:ok, _quest} =
      Thoughts.create_thought(%{
        name: "My Thought",
        trigger: "manual",
        steps: [%{"step_id" => step.id, "flow" => "always"}]
      })

    {:ok, view, html} = live(conn, "/grimoire")
    html_snapshot(view)
    assert html =~ "My Thought"
    assert html =~ "active"
    assert html =~ "manual"
  end

  test "shows run stats for thoughts with runs", %{conn: conn} do
    {:ok, step} = Thoughts.create_synapse(%{name: "Stats Step", trigger: "manual", roster: []})

    {:ok, thought} =
      Thoughts.create_thought(%{
        name: "Stats Thought",
        trigger: "manual",
        steps: [%{"step_id" => step.id, "flow" => "always"}]
      })

    {:ok, _run} = Thoughts.create_daydream(%{thought_id: thought.id, status: "complete"})
    {:ok, _run2} = Thoughts.create_daydream(%{thought_id: thought.id, status: "failed"})

    {:ok, _view, html} = live(conn, "/grimoire")
    assert html =~ "Runs: 2"
    assert html =~ "1 ok"
    assert html =~ "1 failed"
  end

  test "shows thought log and telemetry tabs", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/grimoire")
    assert html =~ "Thought Log"
    assert html =~ "Telemetry"
  end

  test "telemetry tab renders health and stats widgets", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/grimoire")
    assert html =~ "CLI Tools"
    assert html =~ "Sources"
    assert html =~ "Ollama"
    assert html =~ "Uptime"
    assert html =~ "daydreams"
  end

  test "redirects to town square when no banner set", %{conn: conn} do
    ExCortex.Repo.delete_all(ExCortex.Settings)
    {:error, {:live_redirect, %{to: "/town-square"}}} = live(conn, ~p"/grimoire")
  end

  test "shows paused badge for paused thoughts", %{conn: conn} do
    {:ok, step} = Thoughts.create_synapse(%{name: "Paused Step", trigger: "manual", roster: []})

    {:ok, _quest} =
      Thoughts.create_thought(%{
        name: "Paused Thought",
        trigger: "manual",
        status: "paused",
        steps: [%{"step_id" => step.id, "flow" => "always"}]
      })

    {:ok, _view, html} = live(conn, "/grimoire")
    assert html =~ "Paused Thought"
    assert html =~ "paused"
  end

  describe "per-thought drill-down" do
    test "clicking a thought shows its detail view", %{conn: conn} do
      {:ok, step} = Thoughts.create_synapse(%{name: "Drill Step", trigger: "manual", roster: []})

      {:ok, thought} =
        Thoughts.create_thought(%{
          name: "Drill Thought",
          trigger: "manual",
          steps: [%{"step_id" => step.id, "flow" => "always"}]
        })

      {:ok, view, _html} = live(conn, "/grimoire")
      html = render_click(view, "select_quest", %{"id" => to_string(thought.id)})
      assert html =~ "Drill Thought"
      assert html =~ "Run History"
      assert html =~ "Back to Thought Log"
    end

    test "clicking a thought shows its runs and memory entries", %{conn: conn} do
      {:ok, step} = Thoughts.create_synapse(%{name: "Memory Step", trigger: "manual", roster: []})

      {:ok, thought} =
        Thoughts.create_thought(%{
          name: "Memory Thought",
          trigger: "manual",
          steps: [%{"step_id" => step.id, "flow" => "always"}]
        })

      {:ok, _run} = Thoughts.create_daydream(%{thought_id: thought.id, status: "complete"})

      {:ok, _entry} =
        ExCortex.Memory.create_engram(%{
          title: "From drill",
          body: "data",
          tags: [],
          thought_id: thought.id
        })

      {:ok, view, _html} = live(conn, "/grimoire")
      html = render_click(view, "select_quest", %{"id" => to_string(thought.id)})
      assert html =~ "Memory Thought"
      assert html =~ "complete"
      assert html =~ "From drill"
    end

    test "back button returns to overview", %{conn: conn} do
      {:ok, step} = Thoughts.create_synapse(%{name: "Back Step", trigger: "manual", roster: []})

      {:ok, thought} =
        Thoughts.create_thought(%{
          name: "Back Thought",
          trigger: "manual",
          steps: [%{"step_id" => step.id, "flow" => "always"}]
        })

      {:ok, view, _html} = live(conn, "/grimoire")
      render_click(view, "select_quest", %{"id" => to_string(thought.id)})
      html = render_click(view, "back_to_quest_log", %{})
      assert html =~ "Thought Log"
      refute html =~ "Run History"
    end
  end
end
