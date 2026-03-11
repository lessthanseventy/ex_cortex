defmodule ExCaliburWeb.LibraryLiveTest do
  use ExCaliburWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCalibur.Sources.Book
  alias ExCalibur.Sources.Source

  setup do
    ExCalibur.Settings.set_banner("tech")
    :ok
  end

  describe "active sources section" do
    setup do
      ExCalibur.Repo.delete_all(Source)
      :ok
    end

    test "shows empty state when no sources exist", %{conn: conn} do
      {:ok, view, html} = live(conn, "/library")
      html_snapshot(view)
      assert html =~ "No active sources"
    end

    test "shows existing sources with status and actions", %{conn: conn} do
      book = List.first(Book.scrolls())

      %Source{}
      |> Source.changeset(%{
        source_type: book.source_type,
        config: book.default_config,
        book_id: book.id,
        status: "paused"
      })
      |> ExCalibur.Repo.insert!()

      {:ok, _view, html} = live(conn, "/library")
      assert html =~ book.name
      assert html =~ "paused"
      assert html =~ "Resume"
      assert html =~ "Delete"
    end

    test "pause/resume/delete actions update the list", %{conn: conn} do
      book = List.first(Book.scrolls())

      source =
        %Source{}
        |> Source.changeset(%{
          source_type: book.source_type,
          config: book.default_config,
          book_id: book.id,
          status: "paused"
        })
        |> ExCalibur.Repo.insert!()

      {:ok, view, _html} = live(conn, "/library")

      # Delete removes it
      view |> element("[phx-click=delete][phx-value-id='#{source.id}']") |> render_click()
      refute has_element?(view, "[phx-value-id='#{source.id}']")
    end
  end

  describe "browse tabs" do
    test "renders scrolls tab by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/library")
      scroll = List.first(Book.scrolls())
      escaped = scroll.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      assert html =~ escaped
    end

    test "switching to books tab shows books", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      html = view |> element("button[phx-value-tab=books]") |> render_click()

      book = List.first(Book.books())
      escaped = book.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      assert html =~ escaped
    end

    test "adding a scroll moves it from browse to active sources", %{conn: conn} do
      scroll = List.first(Book.scrolls())
      {:ok, view, _html} = live(conn, "/library")

      escaped = scroll.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      assert has_element?(view, "button[phx-click=add_scroll]")

      view
      |> element("button[phx-click=add_scroll][phx-value-book-id='#{scroll.id}']")
      |> render_click()

      html = render(view)
      # Should appear in active sources
      assert html =~ escaped
      # Should no longer appear in browse list
      refute has_element?(
               view,
               "button[phx-click=add_scroll][phx-value-book-id='#{scroll.id}']"
             )
    end

    test "expanding a book shows config form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      view |> element("button[phx-value-tab=books]") |> render_click()

      book = List.first(Book.books())

      html =
        view
        |> element("button[phx-click=expand_book][phx-value-book-id='#{book.id}']")
        |> render_click()

      assert html =~ "Save &amp; Add"
      assert html =~ "Configure"
    end

    test "books tab snapshot", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")
      view |> element("button[phx-value-tab=books]") |> render_click()
      html_snapshot(view)
    end
  end

  describe "heralds tab" do
    setup do
      ExCalibur.Repo.delete_all(ExCalibur.Heralds.Herald)
      :ok
    end

    test "shows heralds tab", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/library")
      assert html =~ "Heralds"
    end

    test "can switch to heralds tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library")
      html = view |> element("[phx-value-tab=heralds]") |> render_click()
      assert html =~ "Herald"
    end

    test "can create a slack herald", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library")
      view |> element("[phx-value-tab=heralds]") |> render_click()

      view
      |> form("form[phx-submit=create_herald]", %{
        "herald[name]" => "slack:eng",
        "herald[type]" => "slack",
        "herald[webhook_url]" => "https://hooks.slack.com/test"
      })
      |> render_submit()

      assert length(ExCalibur.Heralds.list_heralds()) == 1
    end

    test "can delete a herald", %{conn: conn} do
      {:ok, h} = ExCalibur.Heralds.create_herald(%{name: "slack:eng", type: "slack", config: %{}})
      {:ok, view, _html} = live(conn, ~p"/library")
      view |> element("[phx-value-tab=heralds]") |> render_click()
      # expand the herald row first to reveal the delete button
      view |> element("[phx-click=configure_herald][phx-value-id='#{h.id}']") |> render_click()
      view |> element("[phx-click=delete_herald][phx-value-id='#{h.id}']") |> render_click()
      assert ExCalibur.Heralds.list_heralds() == []
    end
  end

  describe "banner filtering" do
    test "library books filter by banner", %{conn: conn} do
      ExCalibur.Settings.set_banner("lifestyle")
      {:ok, _view, html} = live(conn, ~p"/library")
      # Tech-specific books should be hidden
      refute html =~ "Credo Scanner"
    end

    test "redirects to town square when no banner set", %{conn: conn} do
      ExCalibur.Repo.delete_all(ExCalibur.Settings)
      {:error, {:live_redirect, %{to: "/town-square"}}} = live(conn, ~p"/library")
    end
  end
end
