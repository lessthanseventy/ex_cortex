defmodule ExCortexWeb.LodgeLiveTest do
  use ExCortexWeb.ConnCase, async: true
  use Excessibility

  import Phoenix.LiveViewTest

  alias ExCortex.Neurons.Neuron
  alias ExCortex.Signals

  defp insert_member do
    %Neuron{}
    |> Neuron.changeset(%{type: "role", name: "Test Role", status: "active", source: "db", config: %{}})
    |> ExCortex.Repo.insert!()
  end

  describe "index" do
    setup do
      ExCortex.Repo.delete_all(Neuron)
      ExCortex.Settings.set_banner("tech")
      :ok
    end

    test "redirects to town square when no neurons exist", %{conn: conn} do
      {:error, {:live_redirect, %{to: "/town-square"}}} = live(conn, "/lodge")
    end

    test "redirects to town square when no banner set", %{conn: conn} do
      insert_member()
      ExCortex.Repo.delete_all(ExCortex.Settings)
      assert ExCortex.Settings.get_banner() == nil
      {:error, {:live_redirect, %{to: "/town-square"}}} = live(conn, "/lodge")
    end
  end

  describe "card workspace" do
    setup do
      ExCortex.Repo.delete_all(Neuron)
      ExCortex.Settings.set_banner("tech")
      :ok
    end

    test "shows empty state when no cards exist", %{conn: conn} do
      insert_member()
      {:ok, view, html} = live(conn, "/lodge")
      html_snapshot(view)
      assert html =~ "Cortex"
      assert html =~ "No cards yet"
    end

    test "shows cards", %{conn: conn} do
      insert_member()
      Signals.create_signal(%{type: "note", title: "Hello World", body: "test", source: "manual"})
      {:ok, _view, html} = live(conn, "/lodge")
      assert html =~ "Hello World"
    end

    test "can create a note card", %{conn: conn} do
      insert_member()
      {:ok, view, _html} = live(conn, "/lodge")

      view
      |> form("form[phx-submit=create_card]", %{
        "card" => %{"type" => "note", "title" => "New Note", "body" => "content"}
      })
      |> render_submit()

      assert render(view) =~ "New Note"
    end

    test "can dismiss a card", %{conn: conn} do
      insert_member()
      {:ok, card} = Signals.create_signal(%{type: "note", title: "Dismiss Me", source: "manual"})
      {:ok, view, _html} = live(conn, "/lodge")
      assert render(view) =~ "Dismiss Me"

      render_click(view, "dismiss_card", %{"card-id" => to_string(card.id)})
      refute render(view) =~ "Dismiss Me"
    end

    test "displays augury card synced from memory", %{conn: conn} do
      insert_member()

      ExCortex.Memory.create_engram(%{
        title: "World Thesis",
        body: "Markets are shifting",
        tags: ["augury"],
        source: "manual"
      })

      {:ok, _view, html} = live(conn, "/lodge")
      assert html =~ "The Augury"
      assert html =~ "World Thesis"
    end

    test "can toggle pin", %{conn: conn} do
      insert_member()
      {:ok, card} = Signals.create_signal(%{type: "note", title: "Pin Me", source: "manual"})
      {:ok, view, _html} = live(conn, "/lodge")

      render_click(view, "toggle_pin", %{"card-id" => to_string(card.id)})
      html = render(view)
      assert html =~ "pinned" or html =~ "Unpin"
    end

    test "renders pinned cards in grid section", %{conn: conn} do
      insert_member()

      Signals.create_signal(%{
        type: "briefing",
        title: "Pinned Brief",
        body: "Important",
        source: "thought",
        pinned: true,
        pin_slug: "test-pin"
      })

      {:ok, view, _html} = live(conn, "/lodge")
      assert has_element?(view, "h2", "Pinned")
      assert has_element?(view, "span", "Pinned Brief")
    end

    test "renders action_list card with approve/reject buttons", %{conn: conn} do
      insert_member()

      Signals.create_signal(%{
        type: "action_list",
        title: "Cleanup",
        body: "",
        source: "thought",
        metadata: %{
          "items" => [
            %{"id" => "1", "label" => "Old Newsletter", "status" => "pending"},
            %{"id" => "2", "label" => "Security Alerts", "status" => "pending"}
          ],
          "action_labels" => %{"approve" => "Unsubscribe", "reject" => "Keep"}
        }
      })

      {:ok, view, _html} = live(conn, "/lodge")
      assert has_element?(view, "button", "Unsubscribe")
      assert has_element?(view, "button", "Keep")
    end

    test "separates pinned and feed cards", %{conn: conn} do
      insert_member()

      Signals.create_signal(%{
        type: "briefing",
        title: "Pinned Card",
        body: "pinned content",
        source: "thought",
        pinned: true,
        pin_slug: "pinned-one"
      })

      Signals.create_signal(%{
        type: "note",
        title: "Feed Card",
        body: "feed content",
        source: "manual"
      })

      {:ok, view, _html} = live(conn, "/lodge")
      assert has_element?(view, "h2", "Pinned")
      assert has_element?(view, "h2", "Recent")
      assert has_element?(view, "span", "Pinned Card")
      assert has_element?(view, "span", "Feed Card")
    end
  end
end
