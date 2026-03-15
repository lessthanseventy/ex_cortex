defmodule ExCortexWeb.SignalCardsTest do
  use ExCortexWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias ExCortexWeb.Components.SignalCards

  defp render_card(card) do
    assigns = %{card: card}
    rendered_to_string(~H"<SignalCards.signal_card card={@card} />")
  end

  describe "signal_card/1" do
    test "renders note card" do
      card = %{
        type: "note",
        title: "My Note",
        body: "**hello**",
        pinned: false,
        metadata: %{},
        id: 1,
        status: "active"
      }

      html = render_card(card)
      assert html =~ "My Note"
      assert html =~ "<strong>hello</strong>"
    end

    test "renders checklist card with items" do
      card = %{
        type: "checklist",
        title: "TODO",
        body: "",
        pinned: false,
        id: 2,
        status: "active",
        metadata: %{
          "items" => [
            %{"text" => "Buy milk", "checked" => false},
            %{"text" => "Done", "checked" => true}
          ]
        }
      }

      html = render_card(card)
      assert html =~ "TODO"
      assert html =~ "Buy milk"
      assert html =~ "Done"
    end

    test "renders alert card with distinct styling" do
      card = %{
        type: "alert",
        title: "Warning!",
        body: "Disk full",
        pinned: false,
        metadata: %{},
        id: 3,
        status: "active"
      }

      html = render_card(card)
      assert html =~ "Warning!"
      assert html =~ "border-destructive"
    end

    test "renders link card" do
      card = %{
        type: "link",
        title: "Docs",
        body: "Reference",
        pinned: false,
        metadata: %{"url" => "https://example.com"},
        id: 4,
        status: "active"
      }

      html = render_card(card)
      assert html =~ "Docs"
      assert html =~ "https://example.com"
    end

    test "renders proposal card with actions" do
      card = %{
        type: "proposal",
        title: "Change roster",
        body: "Narrow to masters",
        pinned: false,
        id: 5,
        status: "active",
        metadata: %{"proposal_type" => "roster_change", "proposal_id" => 42}
      }

      html = render_card(card)
      assert html =~ "Change roster"
      assert html =~ "Approve"
      assert html =~ "Reject"
    end

    test "renders meeting card" do
      card = %{
        type: "meeting",
        title: "Standup",
        body: "Daily sync",
        pinned: false,
        id: 6,
        status: "active",
        metadata: %{"attendees" => ["Alice", "Bob"], "agenda" => ["Status", "Blockers"]}
      }

      html = render_card(card)
      assert html =~ "Standup"
      assert html =~ "Alice"
    end

    test "shows pin indicator" do
      card = %{
        type: "note",
        title: "Pinned",
        body: "",
        pinned: true,
        metadata: %{},
        id: 7,
        status: "active"
      }

      html = render_card(card)
      assert html =~ "pinned"
    end
  end
end
