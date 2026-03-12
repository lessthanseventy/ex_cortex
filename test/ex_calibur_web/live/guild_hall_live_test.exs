defmodule ExCaliburWeb.GuildHallLiveTest do
  use ExCaliburWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCalibur.Repo
  alias Excellence.Schemas.Member

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

    {:ok, member} = Repo.insert(struct(Member, Map.merge(defaults, attrs)))
    member
  end

  setup do
    ExCalibur.Settings.set_banner("tech")
    :ok
  end

  describe "index" do
    test "renders guild hall page header", %{conn: conn} do
      {:ok, view, html} = live(conn, "/guild-hall")
      html_snapshot(view)
      assert html =~ "Guild Hall"
      assert html =~ "+ Custom Member"
    end

    test "shows empty state when no members in DB", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/guild-hall")
      # No DB members — no expandable member cards shown
      refute html =~ "phx-click=\"toggle_expand\""
    end

    test "shows DB member on page", %{conn: conn} do
      insert_member(%{name: "Grammar Editor"})
      {:ok, _view, html} = live(conn, "/guild-hall")
      assert html =~ "Grammar Editor"
    end

    test "shows builtin member name when member_id is set", %{conn: conn} do
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

      {:ok, _view, html} = live(conn, "/guild-hall")
      # Builtin name from BuiltinMember.get/1 should appear (or fallback to DB name)
      assert html =~ "Grammar Editor"
    end

    test "active members appear before inactive ones", %{conn: conn} do
      insert_member(%{name: "Alpha Active", status: "active"})
      insert_member(%{name: "Beta Inactive", status: "draft"})
      {:ok, _view, html} = live(conn, "/guild-hall")
      active_pos = html |> :binary.match("Alpha Active") |> elem(0)
      inactive_pos = html |> :binary.match("Beta Inactive") |> elem(0)
      assert active_pos < inactive_pos
    end

    test "shows rank pill for each member", %{conn: conn} do
      insert_member(%{config: %{"rank" => "master", "model" => "", "strategy" => "cot", "system_prompt" => ""}})
      {:ok, _view, html} = live(conn, "/guild-hall")
      assert html =~ "Master"
    end
  end

  describe "card UI" do
    test "clicking member row expands it", %{conn: conn} do
      member = insert_member()
      {:ok, view, _html} = live(conn, "/guild-hall")
      id = to_string(member.id)
      html = view |> element(~s([phx-click="toggle_expand"][phx-value-id="#{id}"])) |> render_click()
      assert html =~ "member[system_prompt]"
    end

    test "clicking expanded member collapses it", %{conn: conn} do
      member = insert_member()
      {:ok, view, _html} = live(conn, "/guild-hall")
      id = to_string(member.id)
      view |> element(~s([phx-click="toggle_expand"][phx-value-id="#{id}"])) |> render_click()
      html = view |> element(~s([phx-click="toggle_expand"][phx-value-id="#{id}"])) |> render_click()
      refute html =~ "member[system_prompt]"
    end
  end

  describe "events" do
    test "toggle_active deactivates an active member", %{conn: conn} do
      member = insert_member(%{status: "active"})
      id = to_string(member.id)
      {:ok, view, _html} = live(conn, "/guild-hall")

      view
      |> element(~s([phx-click="toggle_active"][phx-value-id="#{id}"]))
      |> render_click(%{"id" => id, "active" => "true"})

      updated = Repo.get!(Member, member.id)
      assert updated.status == "draft"
    end

    test "toggle_active activates an inactive member", %{conn: conn} do
      member = insert_member(%{status: "draft"})
      id = to_string(member.id)
      {:ok, view, _html} = live(conn, "/guild-hall")

      view
      |> element(~s([phx-click="toggle_active"][phx-value-id="#{id}"]))
      |> render_click(%{"id" => id, "active" => "false"})

      updated = Repo.get!(Member, member.id)
      assert updated.status == "active"
    end

    test "add_new shows new member form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/guild-hall")
      html = render_click(view, "set_section", %{"section" => "custom"})
      html_snapshot(view)
      assert html =~ "Create Member"
    end

    test "cancel_new hides new member form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/guild-hall")
      render_click(view, "set_section", %{"section" => "custom"})
      html = render_click(view, "set_section", %{"section" => "all"})
      refute html =~ "Create Member"
    end

    test "create_member inserts a new DB member", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/guild-hall")
      render_click(view, "set_section", %{"section" => "custom"})

      html =
        view
        |> form("form[phx-submit=\"create_member\"]", %{
          "member" => %{
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
      member = insert_member()
      id = to_string(member.id)
      {:ok, view, _html} = live(conn, "/guild-hall")

      view |> element(~s([phx-click="toggle_expand"][phx-value-id="#{id}"])) |> render_click()

      view
      |> form("form[phx-submit=\"save_member\"]", %{
        "member" => %{
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

      updated = Repo.get!(Member, member.id)
      assert updated.config["system_prompt"] == "Updated prompt."
      assert updated.config["rank"] == "master"
    end

    test "delete_member removes member from page", %{conn: conn} do
      member = insert_member(%{name: "Deletable Role"})
      db_id = to_string(member.id)
      {:ok, view, _html} = live(conn, "/guild-hall")
      html = render_click(view, "delete_member", %{"id" => db_id})
      refute html =~ "Deletable Role"
    end
  end

  describe "recruitment" do
    test "shows recruit sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/guild-hall")
      assert html =~ "Recruit a Member"
      assert html =~ "Editors"
      assert html =~ "Analysts"
    end

    test "recruit button creates a member and updates the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/guild-hall")
      # Click recruit for the first builtin member at apprentice rank
      first = hd(ExCalibur.Members.BuiltinMember.editors())
      html = render_click(view, "recruit", %{"member-id" => first.id, "rank" => "apprentice"})
      # Flash appears and member shows in the updated member list
      assert html =~ "recruited!"
      assert Repo.get_by(Member, name: first.name)
    end
  end

  describe "banner filtering" do
    test "builtin member catalog filters by banner", %{conn: conn} do
      ExCalibur.Settings.set_banner("lifestyle")
      {:ok, _view, html} = live(conn, ~p"/guild-hall")
      # Tech specialists should not appear in lifestyle banner
      refute html =~ "Frontend Reviewer"
    end

    test "redirects to town square when no banner set", %{conn: conn} do
      Repo.delete_all(ExCalibur.Settings)
      {:error, {:live_redirect, %{to: "/town-square"}}} = live(conn, ~p"/guild-hall")
    end
  end

  describe "markdown rendering" do
    test "charter text renders as markdown", %{conn: conn} do
      ExCalibur.GuildCharters.upsert_charter("test-guild", "**bold charter** rules")
      {:ok, _view, html} = live(conn, ~p"/guild-hall")
      assert html =~ "<strong>bold charter</strong>"
    end
  end
end
