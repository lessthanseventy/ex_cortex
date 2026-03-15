defmodule ExCortexWeb.AccessibilityTest do
  @moduledoc "Accessibility snapshot tests for all LiveView pages."
  use ExCortexWeb.ConnCase
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCortex.Clusters
  alias ExCortex.Memory
  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo
  alias ExCortex.Ruminations
  alias ExCortex.Senses.Sense
  alias ExCortex.Signals
  alias ExCortex.Thoughts

  # Seed minimal data so pages render non-empty states
  setup do
    {:ok, _} = Clusters.upsert_pathway("Test Cluster", "A cluster for testing accessibility.")

    {:ok, _} =
      Repo.insert(
        Neuron.changeset(%Neuron{}, %{
          name: "Test Neuron",
          team: "Test Cluster",
          type: "role",
          status: "active",
          config: %{
            "system_prompt" => "You are a test neuron.",
            "rank" => "apprentice",
            "model" => "ministral-3:8b"
          }
        })
      )

    {:ok, synapse} =
      Ruminations.create_synapse(%{
        name: "Test Step",
        description: "A test synapse.",
        trigger: "manual",
        output_type: "freeform",
        cluster_name: "Test Cluster",
        roster: [%{"who" => "all", "how" => "solo", "when" => "sequential"}]
      })

    {:ok, _} =
      Ruminations.create_rumination(%{
        name: "Test Rumination",
        description: "A rumination for testing.",
        trigger: "manual",
        status: "paused",
        steps: [%{"step_id" => synapse.id, "order" => 1}]
      })

    {:ok, _} =
      Memory.create_engram(%{
        title: "Test Engram",
        body: "Body of test engram.",
        impression: "A test memory.",
        recall: "Detailed test recall content.",
        category: "semantic",
        source: "manual",
        tags: ["test"]
      })

    {:ok, _} =
      Signals.create_signal(%{
        type: "note",
        title: "Test Signal",
        body: "A test signal for accessibility.",
        source: "test",
        tags: ["test"]
      })

    {:ok, _} =
      Thoughts.create_thought(%{
        question: "What is a test?",
        answer: "A test verifies correctness.",
        scope: "muse",
        status: "saved",
        tags: ["test"]
      })

    {:ok, _} =
      Repo.insert(
        Sense.changeset(%Sense{}, %{
          name: "Test Sense",
          source_type: "cortex",
          status: "paused",
          config: %{"interval" => 3_600_000}
        })
      )

    :ok
  end

  # -- Dashboard --

  test "cortex dashboard is accessible", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/cortex")
    html_snapshot(view)
    assert html =~ "Signals"
    assert html =~ "Cluster Health"
  end

  # -- Wonder --

  test "wonder page is accessible", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/wonder")
    html_snapshot(view)
    assert html =~ "Wonder"
  end

  # -- Muse --

  test "muse page is accessible", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/muse")
    html_snapshot(view)
    assert html =~ "Muse"
  end

  # -- Thoughts --

  test "thoughts page is accessible", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/thoughts")
    html_snapshot(view)
    assert html =~ "Thoughts"
  end

  # -- Neurons --

  test "neurons page is accessible", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/neurons")
    html_snapshot(view)
    assert html =~ "Neurons"
    assert html =~ "Test Cluster"
  end

  test "neurons page with selected neuron is accessible", %{conn: conn} do
    neuron = Repo.one!(Neuron)
    {:ok, view, _html} = live(conn, ~p"/neurons")
    html = render_click(view, "select_cluster", %{"cluster" => "Test Cluster"})
    assert html =~ "Test Neuron"
    html = render_click(view, "select_neuron", %{"id" => to_string(neuron.id)})
    html_snapshot(view)
    assert html =~ "SYSTEM PROMPT"
  end

  test "neurons edit form is accessible", %{conn: conn} do
    neuron = Repo.one!(Neuron)
    {:ok, view, _html} = live(conn, ~p"/neurons")
    render_click(view, "select_cluster", %{"cluster" => "Test Cluster"})
    render_click(view, "select_neuron", %{"id" => to_string(neuron.id)})
    html = render_click(view, "edit_neuron")
    html_snapshot(view)
    assert html =~ "Editing:"
  end

  # -- Ruminations --

  test "ruminations page is accessible", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/ruminations")
    html_snapshot(view)
    assert html =~ "Ruminations"
    assert html =~ "Test Rumination"
  end

  test "ruminations detail view is accessible", %{conn: conn} do
    rumination = Repo.one!(ExCortex.Ruminations.Rumination)
    {:ok, view, _html} = live(conn, ~p"/ruminations")
    html = render_click(view, "select_rumination", %{"id" => to_string(rumination.id)})
    html_snapshot(view)
    assert html =~ "Test Step"
    assert html =~ "Synapse Chain"
  end

  # -- Memory --

  test "memory page is accessible", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/memory")
    html_snapshot(view)
    assert html =~ "Memory"
    assert html =~ "Test Engram"
  end

  # -- Senses --

  test "senses page is accessible", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/senses")
    html_snapshot(view)
    assert html =~ "Senses"
  end

  # -- Instinct --

  test "instinct page is accessible", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/instinct")
    html_snapshot(view)
    assert html =~ "Instinct"
  end

  # -- Settings --

  test "settings page is accessible", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/settings")
    html_snapshot(view)
    assert html =~ "Settings"
  end

  # -- Guide --

  test "guide page is accessible", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/guide")
    html_snapshot(view)
    assert html =~ "Guide"
  end

  # -- Evaluate --

  test "evaluate page is accessible", %{conn: conn} do
    case live(conn, ~p"/evaluate") do
      {:ok, view, html} ->
        html_snapshot(view)
        assert html =~ "Evaluate"

      {:error, {:live_redirect, %{to: to}}} ->
        # Evaluate may redirect when no clusters are configured for direct eval
        {:ok, view, html} = live(conn, to)
        html_snapshot(view)
        assert html
    end
  end
end
