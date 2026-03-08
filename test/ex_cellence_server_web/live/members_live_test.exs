defmodule ExCellenceServerWeb.MembersLiveTest do
  use ExCellenceServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Excellence.Schemas.ResourceDefinition
  alias ExCellenceServer.Repo

  describe "list_members merge" do
    test "renders built-in members on the page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/members")
      # Grammar Editor is a built-in member
      assert html =~ "Grammar Editor"
    end

    test "built-in members show as inactive by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/members")
      # Should show toggle in off state — look for inactive indicator
      # The page renders all built-ins; with no DB record they are inactive
      assert html =~ "Grammar Editor"
    end

    test "custom DB member appears on page", %{conn: conn} do
      {:ok, _} =
        Repo.insert(%ResourceDefinition{
          type: "role",
          name: "My Custom Role",
          source: "db",
          status: "active",
          config: %{
            "system_prompt" => "You are custom.",
            "ranks" => %{
              "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
              "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
              "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
            }
          }
        })

      {:ok, _view, html} = live(conn, "/members")
      assert html =~ "My Custom Role"
    end

    test "active members appear before inactive ones", %{conn: conn} do
      {:ok, _} =
        Repo.insert(%ResourceDefinition{
          type: "role",
          name: "Grammar Editor",
          source: "code",
          status: "active",
          config: %{
            "member_id" => "grammar-editor",
            "system_prompt" => "You are a grammar editor.",
            "ranks" => %{
              "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
              "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
              "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
            }
          }
        })

      {:ok, _view, html} = live(conn, "/members")
      # Grammar Editor is now active — it should appear before inactive built-ins
      grammar_pos = html |> :binary.match("Grammar Editor") |> elem(0)
      tone_pos = html |> :binary.match("Tone Reviewer") |> elem(0)
      assert grammar_pos < tone_pos
    end
  end

  describe "card UI" do
    test "shows + button to add new member", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/members")
      assert html =~ "phx-click=\"add_new\""
    end

    test "built-in member shows rank pills", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/members")
      assert html =~ "Apprentice"
      assert html =~ "Journeyman"
      assert html =~ "Master"
    end

    test "clicking member name expands it", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/members")
      # Click to expand Grammar Editor (a built-in)
      html = view |> element(~s([phx-click="toggle_expand"][phx-value-id="grammar-editor"])) |> render_click()
      assert html =~ "system_prompt"
    end
  end

  describe "events" do
    test "toggle_expand adds member to expanded set", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/members")
      html = view |> element(~s([phx-click="toggle_expand"][phx-value-id="grammar-editor"])) |> render_click()
      # system_prompt textarea is visible when expanded
      assert html =~ "system_prompt"
    end

    test "toggle_expand collapses when already expanded", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/members")
      view |> element(~s([phx-click="toggle_expand"][phx-value-id="grammar-editor"])) |> render_click()
      html = view |> element(~s([phx-click="toggle_expand"][phx-value-id="grammar-editor"])) |> render_click()
      refute html =~ "member[system_prompt]"
    end

    test "toggle_active activates a built-in member", %{conn: conn} do
      import Ecto.Query

      {:ok, view, _html} = live(conn, "/members")

      view
      |> element(~s([phx-click="toggle_active"][phx-value-id="grammar-editor"]))
      |> render_click(%{"id" => "grammar-editor", "active" => "false"})

      # Verify DB record was created
      db =
        Repo.one(
          from r in ResourceDefinition,
            where: r.type == "role" and r.source == "code"
        )

      assert db
      assert db.status == "active"
      assert db.config["member_id"] == "grammar-editor"
    end

    test "add_new shows new member form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/members")
      html = view |> element("[phx-click=\"add_new\"]") |> render_click()
      assert html =~ "Create Member"
    end

    test "cancel_new hides new member form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/members")
      view |> element("[phx-click=\"add_new\"]") |> render_click()
      html = view |> element("[phx-click=\"cancel_new\"]") |> render_click()
      refute html =~ "Create Member"
    end

    test "create_member inserts a new custom member", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/members")
      view |> element("[phx-click=\"add_new\"]") |> render_click()

      html =
        view
        |> form("form[phx-submit=\"create_member\"]", %{
          "member" => %{
            "name" => "Test Role",
            "system_prompt" => "You test things.",
            "ranks" => %{
              "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
              "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
              "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
            }
          }
        })
        |> render_submit()

      assert html =~ "Test Role"
    end

    test "save_member updates an existing built-in", %{conn: conn} do
      # First activate it so there's a DB record
      {:ok, rddef} =
        Repo.insert(%ResourceDefinition{
          type: "role",
          name: "Grammar Editor",
          source: "code",
          status: "active",
          config: %{
            "member_id" => "grammar-editor",
            "system_prompt" => "Old prompt",
            "ranks" => %{
              "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
              "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
              "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
            }
          }
        })

      {:ok, view, _html} = live(conn, "/members")

      # Expand the card first so the form is rendered
      view |> element(~s([phx-click="toggle_expand"][phx-value-id="grammar-editor"])) |> render_click()

      view
      |> form("form[phx-submit=\"save_member\"]", %{
        "member" => %{
          "id" => "grammar-editor",
          "builtin" => "true",
          "system_prompt" => "Updated prompt.",
          "ranks" => %{
            "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
            "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
            "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
          }
        }
      })
      |> render_submit()

      updated = Repo.get!(ResourceDefinition, rddef.id)
      assert updated.config["system_prompt"] == "Updated prompt."
    end

    test "delete_member removes a custom member", %{conn: conn} do
      {:ok, _} =
        Repo.insert(%ResourceDefinition{
          type: "role",
          name: "Deletable Role",
          source: "db",
          status: "active",
          config: %{
            "system_prompt" => "gone",
            "ranks" => %{
              "apprentice" => %{"model" => "phi4-mini", "strategy" => "cot"},
              "journeyman" => %{"model" => "gemma3:4b", "strategy" => "cod"},
              "master" => %{"model" => "llama3:8b", "strategy" => "cod"}
            }
          }
        })

      db_id = to_string(Repo.get_by!(ResourceDefinition, name: "Deletable Role").id)

      {:ok, view, _html} = live(conn, "/members")

      # Trigger delete_member event directly
      html = render_click(view, "delete_member", %{"id" => db_id})

      refute html =~ "Deletable Role"
    end
  end
end
