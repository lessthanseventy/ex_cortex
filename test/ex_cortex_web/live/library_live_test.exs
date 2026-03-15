defmodule ExCortexWeb.LibraryLiveTest do
  use ExCortexWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCortex.Senses.Reflex
  alias ExCortex.Senses.Sense

  setup do
    ExCortex.Settings.set_banner("tech")
    :ok
  end

  describe "active sources section" do
    setup do
      ExCortex.Repo.delete_all(Sense)
      :ok
    end

    test "shows empty state when no sources exist", %{conn: conn} do
      {:ok, view, html} = live(conn, "/library")
      html_snapshot(view)
      assert html =~ "No active sources"
    end

    test "shows existing sources with status and actions", %{conn: conn} do
      reflex = List.first(Reflex.streams())

      %Sense{}
      |> Sense.changeset(%{
        source_type: reflex.source_type,
        config: reflex.default_config,
        book_id: reflex.id,
        status: "paused"
      })
      |> ExCortex.Repo.insert!()

      {:ok, _view, html} = live(conn, "/library")
      assert html =~ reflex.name
      assert html =~ "paused"
      assert html =~ "Resume"
      assert html =~ "Delete"
    end

    test "pause/resume/delete actions update the list", %{conn: conn} do
      reflex = List.first(Reflex.streams())

      source =
        %Sense{}
        |> Sense.changeset(%{
          source_type: reflex.source_type,
          config: reflex.default_config,
          book_id: reflex.id,
          status: "paused"
        })
        |> ExCortex.Repo.insert!()

      {:ok, view, _html} = live(conn, "/library")

      # Delete removes it
      view |> element("[phx-click=delete][phx-value-id='#{source.id}']") |> render_click()
      refute has_element?(view, "[phx-value-id='#{source.id}']")
    end
  end

  describe "browse tabs" do
    test "renders streams tab by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/library")
      scroll = List.first(Reflex.streams())
      escaped = scroll.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      assert html =~ escaped
    end

    test "switching to reflexes tab shows reflexes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      html = view |> element("button[phx-value-tab=reflexes]") |> render_click()

      reflex = List.first(Reflex.reflexes())
      escaped = reflex.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      assert html =~ escaped
    end

    test "adding a scroll moves it from browse to active sources", %{conn: conn} do
      scroll = List.first(Reflex.streams())
      {:ok, view, _html} = live(conn, "/library")

      escaped = scroll.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      assert has_element?(view, "button[phx-click=add_stream]")

      view
      |> element("button[phx-click=add_stream][phx-value-reflex-id='#{scroll.id}']")
      |> render_click()

      html = render(view)
      # Should appear in active sources
      assert html =~ escaped
      # Should no longer appear in browse list
      refute has_element?(
               view,
               "button[phx-click=add_stream][phx-value-reflex-id='#{scroll.id}']"
             )
    end

    test "expanding a reflex shows config form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      view |> element("button[phx-value-tab=reflexes]") |> render_click()

      reflex = List.first(Reflex.reflexes())

      html =
        view
        |> element("button[phx-click=expand_reflex][phx-value-reflex-id='#{reflex.id}']")
        |> render_click()

      assert html =~ "Save &amp; Add"
      assert html =~ "Configure"
    end

    test "reflexes tab snapshot", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")
      view |> element("button[phx-value-tab=reflexes]") |> render_click()
      html_snapshot(view)
    end
  end

  describe "expressions tab" do
    setup do
      ExCortex.Repo.delete_all(ExCortex.Expressions.Expression)
      :ok
    end

    test "shows expressions tab", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/library")
      assert html =~ "Expressions"
    end

    test "can switch to expressions tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library")
      html = view |> element("[phx-value-tab=expressions]") |> render_click()
      assert html =~ "Expression"
    end

    test "can create a slack expression", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library")
      view |> element("[phx-value-tab=expressions]") |> render_click()

      view
      |> form("form[phx-submit=create_expression]", %{
        "expression[name]" => "slack:eng",
        "expression[type]" => "slack",
        "expression[webhook_url]" => "https://hooks.slack.com/test"
      })
      |> render_submit()

      assert length(ExCortex.Expressions.list_expressions()) == 1
    end

    test "can delete a expression", %{conn: conn} do
      {:ok, h} = ExCortex.Expressions.create_expression(%{name: "slack:eng", type: "slack", config: %{}})
      {:ok, view, _html} = live(conn, ~p"/library")
      view |> element("[phx-value-tab=expressions]") |> render_click()
      # expand the expression row first to reveal the delete button
      view |> element("[phx-click=configure_expression][phx-value-id='#{h.id}']") |> render_click()
      view |> element("[phx-click=delete_expression][phx-value-id='#{h.id}']") |> render_click()
      assert ExCortex.Expressions.list_expressions() == []
    end
  end

  describe "banner filtering" do
    test "senses reflexes filter by banner", %{conn: conn} do
      ExCortex.Settings.set_banner("lifestyle")
      {:ok, _view, html} = live(conn, ~p"/library")
      # Tech-specific reflexes should be hidden
      refute html =~ "Credo Scanner"
    end

    test "redirects to town square when no banner set", %{conn: conn} do
      ExCortex.Repo.delete_all(ExCortex.Settings)
      {:error, {:live_redirect, %{to: "/town-square"}}} = live(conn, ~p"/library")
    end
  end
end
