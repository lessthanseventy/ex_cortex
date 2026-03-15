defmodule ExCortexWeb.GuildHallLiveTest do
  use ExCortexWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo

  defp insert_member(attrs \\ %{}) do
    defaults = %{
      type: "role",
      name: "Test Role",
      source: "db",
      status: "active",
      config: %{
        "system_prompt" => "You are a tester.",
        "rank" => "journeyman",
        "model" => "phi4-mini",
        "strategy" => "cot"
      }
    }

    {:ok, neuron} = Repo.insert(struct(Neuron, Map.merge(defaults, attrs)))
    neuron
  end

  setup do
    ExCortex.Settings.set_banner("tech")
    :ok
  end

  describe "index" do
    test "renders cluster hall page header", %{conn: conn} do
      {:ok, view, html} = live(conn, "/cluster-hall")
      html_snapshot(view)
      assert html =~ "Cluster Hall"
      assert html =~ "+ Custom Neuron"
    end

    test "shows empty state when no neurons in DB", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/cluster-hall")
      # No DB neurons — no expandable neuron cards shown
      refute html =~ "phx-click=\"toggle_expand\""
    end

    test "shows DB neuron on page", %{conn: conn} do
      insert_member(%{name: "Grammar Editor"})
      {:ok, _view, html} = live(conn, "/cluster-hall")
      assert html =~ "Grammar Editor"
    end

    test "shows builtin neuron name when member_id is set", %{conn: conn} do
      insert_member(%{
        name: "Grammar Editor",
        source: "code",
        config: %{
          "member_id" => "grammar-editor",
          "system_prompt" => "You edit grammar.",
          "rank" => "journeyman",
          "model" => "phi4-mini",
          "strategy" => "cot"
        }
      })

      {:ok, _view, html} = live(conn, "/cluster-hall")
      # Builtin name from Builtin.get/1 should appear (or fallback to DB name)
      assert html =~ "Grammar Editor"
    end

    test "active neurons appear before inactive ones", %{conn: conn} do
      insert_member(%{name: "Alpha Active", status: "active"})
      insert_member(%{name: "Beta Inactive", status: "draft"})
      {:ok, _view, html} = live(conn, "/cluster-hall")
      active_pos = html |> :binary.match("Alpha Active") |> elem(0)
      inactive_pos = html |> :binary.match("Beta Inactive") |> elem(0)
      assert active_pos < inactive_pos
    end

    test "shows rank pill for each neuron", %{conn: conn} do
      insert_member(%{config: %{"rank" => "master", "model" => "", "strategy" => "cot", "system_prompt" => ""}})
      {:ok, _view, html} = live(conn, "/cluster-hall")
      assert html =~ "Master"
    end
  end

  describe "card UI" do
    test "clicking neuron row expands it", %{conn: conn} do
      neuron = insert_member()
      {:ok, view, _html} = live(conn, "/cluster-hall")
      id = to_string(neuron.id)
      html = view |> element(~s([phx-click="toggle_expand"][phx-value-id="#{id}"])) |> render_click()
      assert html =~ "neuron[system_prompt]"
    end

    test "clicking expanded neuron collapses it", %{conn: conn} do
      neuron = insert_member()
      {:ok, view, _html} = live(conn, "/cluster-hall")
      id = to_string(neuron.id)
      view |> element(~s([phx-click="toggle_expand"][phx-value-id="#{id}"])) |> render_click()
      html = view |> element(~s([phx-click="toggle_expand"][phx-value-id="#{id}"])) |> render_click()
      refute html =~ "neuron[system_prompt]"
    end
  end

  describe "events" do
    test "toggle_active deactivates an active neuron", %{conn: conn} do
      neuron = insert_member(%{status: "active"})
      id = to_string(neuron.id)
      {:ok, view, _html} = live(conn, "/cluster-hall")

      view
      |> element(~s([phx-click="toggle_active"][phx-value-id="#{id}"]))
      |> render_click(%{"id" => id, "active" => "true"})

      updated = Repo.get!(Neuron, neuron.id)
      assert updated.status == "draft"
    end

    test "toggle_active activates an inactive neuron", %{conn: conn} do
      neuron = insert_member(%{status: "draft"})
      id = to_string(neuron.id)
      {:ok, view, _html} = live(conn, "/cluster-hall")

      view
      |> element(~s([phx-click="toggle_active"][phx-value-id="#{id}"]))
      |> render_click(%{"id" => id, "active" => "false"})

      updated = Repo.get!(Neuron, neuron.id)
      assert updated.status == "active"
    end

    test "add_new shows new neuron form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cluster-hall")
      html = render_click(view, "set_section", %{"section" => "custom"})
      html_snapshot(view)
      assert html =~ "Create Neuron"
    end

    test "cancel_new hides new neuron form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cluster-hall")
      render_click(view, "set_section", %{"section" => "custom"})
      html = render_click(view, "set_section", %{"section" => "all"})
      refute html =~ "Create Neuron"
    end

    test "create_member inserts a new DB neuron", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cluster-hall")
      render_click(view, "set_section", %{"section" => "custom"})

      html =
        view
        |> form("form[phx-submit=\"create_member\"]", %{
          "neuron" => %{
            "name" => "Brand New Role",
            "system_prompt" => "You do new things.",
            "rank" => "journeyman",
            "model" => "gemma3:4b",
            "strategy" => "cot"
          }
        })
        |> render_submit()

      assert html =~ "Brand New Role"
    end

    test "save_member updates system_prompt", %{conn: conn} do
      neuron = insert_member()
      id = to_string(neuron.id)
      {:ok, view, _html} = live(conn, "/cluster-hall")

      view |> element(~s([phx-click="toggle_expand"][phx-value-id="#{id}"])) |> render_click()

      view
      |> form("form[phx-submit=\"save_member\"]", %{
        "neuron" => %{
          "id" => id,
          "builtin" => "false",
          "name" => "Test Role",
          "system_prompt" => "Updated prompt.",
          "rank" => "master",
          "model" => "gemma3:4b",
          "strategy" => "cod"
        }
      })
      |> render_submit()

      updated = Repo.get!(Neuron, neuron.id)
      assert updated.config["system_prompt"] == "Updated prompt."
      assert updated.config["rank"] == "master"
    end

    test "delete_member removes neuron from page", %{conn: conn} do
      neuron = insert_member(%{name: "Deletable Role"})
      db_id = to_string(neuron.id)
      {:ok, view, _html} = live(conn, "/cluster-hall")
      html = render_click(view, "delete_member", %{"id" => db_id})
      refute html =~ "Deletable Role"
    end
  end

  describe "recruitment" do
    test "shows recruit sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/cluster-hall")
      assert html =~ "Recruit a Neuron"
      assert html =~ "Editors"
      assert html =~ "Analysts"
    end

    test "recruit button creates a neuron and updates the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/cluster-hall")
      # Click recruit for the first builtin neuron at apprentice rank
      first = hd(ExCortex.Neurons.Builtin.editors())
      html = render_click(view, "recruit", %{"neuron-id" => first.id, "rank" => "apprentice"})
      # Flash appears and neuron shows in the updated neuron list
      assert html =~ "recruited!"
      assert Repo.get_by(Neuron, name: first.name)
    end
  end

  describe "banner filtering" do
    test "builtin neuron catalog filters by banner", %{conn: conn} do
      ExCortex.Settings.set_banner("lifestyle")
      {:ok, _view, html} = live(conn, ~p"/cluster-hall")
      # Tech specialists should not appear in lifestyle banner
      refute html =~ "Frontend Reviewer"
    end

    test "redirects to town square when no banner set", %{conn: conn} do
      Repo.delete_all(ExCortex.Settings)
      {:error, {:live_redirect, %{to: "/town-square"}}} = live(conn, ~p"/cluster-hall")
    end
  end

  describe "markdown rendering" do
    test "pathway text renders as markdown", %{conn: conn} do
      ExCortex.Clusters.upsert_charter("test-cluster", "**bold pathway** rules")
      {:ok, _view, html} = live(conn, ~p"/cluster-hall")
      assert html =~ "<strong>bold pathway</strong>"
    end
  end
end
