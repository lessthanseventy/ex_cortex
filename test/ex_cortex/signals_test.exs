defmodule ExCortex.SignalsTest do
  use ExCortex.DataCase

  alias ExCortex.Signals

  describe "list_cards/1" do
    test "returns active cards ordered by pinned desc, inserted_at desc" do
      {:ok, pinned} = Signals.create_signal(%{type: "note", title: "Pinned", source: "manual", pinned: true})
      {:ok, _recent} = Signals.create_signal(%{type: "note", title: "Recent", source: "manual"})
      {:ok, _dismissed} = Signals.create_signal(%{type: "note", title: "Gone", source: "manual", status: "dismissed"})

      cards = Signals.list_signals()
      assert length(cards) == 2
      assert hd(cards).id == pinned.id
    end

    test "filters by type" do
      {:ok, _} = Signals.create_signal(%{type: "note", title: "A", source: "manual"})
      {:ok, _} = Signals.create_signal(%{type: "alert", title: "B", source: "manual"})

      cards = Signals.list_signals(type: "note")
      assert length(cards) == 1
      assert hd(cards).type == "note"
    end

    test "filters by tags" do
      {:ok, _} = Signals.create_signal(%{type: "note", title: "Tagged", source: "manual", tags: ["tech", "urgent"]})
      {:ok, _} = Signals.create_signal(%{type: "note", title: "Other", source: "manual", tags: ["idea"]})
      {:ok, _} = Signals.create_signal(%{type: "note", title: "None", source: "manual"})

      cards = Signals.list_signals(tags: ["tech"])
      assert length(cards) == 1
      assert hd(cards).title == "Tagged"

      cards = Signals.list_signals(tags: ["tech", "idea"])
      assert length(cards) == 2
    end
  end

  describe "create_card/1" do
    test "creates a card" do
      {:ok, card} = Signals.create_signal(%{type: "note", title: "Hello", body: "world", source: "manual"})
      assert card.id
      assert card.type == "note"
      assert card.status == "active"
    end
  end

  describe "update_card/2" do
    test "updates a card" do
      {:ok, card} = Signals.create_signal(%{type: "note", title: "Old", source: "manual"})
      {:ok, updated} = Signals.update_signal(card, %{title: "New"})
      assert updated.title == "New"
    end
  end

  describe "dismiss_card/1" do
    test "sets status to dismissed" do
      {:ok, card} = Signals.create_signal(%{type: "note", title: "Bye", source: "manual"})
      {:ok, dismissed} = Signals.dismiss_signal(card)
      assert dismissed.status == "dismissed"
    end
  end

  describe "toggle_pin/1" do
    test "toggles pinned state" do
      {:ok, card} = Signals.create_signal(%{type: "note", title: "Pin me", source: "manual"})
      refute card.pinned
      {:ok, pinned} = Signals.toggle_pin(card)
      assert pinned.pinned
      {:ok, unpinned} = Signals.toggle_pin(pinned)
      refute unpinned.pinned
    end
  end

  describe "post_card/1" do
    test "creates a card and broadcasts" do
      Phoenix.PubSub.subscribe(ExCortex.PubSub, "cortex")
      {:ok, card} = Signals.post_signal(%{type: "alert", title: "Urgent", source: "thought"})
      assert card.id
      assert_receive {:signal_posted, ^card}
    end
  end

  describe "toggle_checklist_item/3" do
    test "toggles a checklist item" do
      {:ok, card} =
        Signals.create_signal(%{
          type: "checklist",
          title: "TODO",
          source: "manual",
          metadata: %{"items" => [%{"text" => "A", "checked" => false}, %{"text" => "B", "checked" => true}]}
        })

      {:ok, updated} = Signals.toggle_checklist_item(card, 0)
      assert Enum.at(updated.metadata["items"], 0)["checked"] == true
      assert Enum.at(updated.metadata["items"], 1)["checked"] == true
    end
  end

  describe "sync_proposals/0" do
    test "creates cards for pending proposals that don't have cards yet" do
      {:ok, step} =
        ExCortex.Ruminations.create_synapse(%{name: "Sync Step", trigger: "manual", roster: []})

      {:ok, proposal} =
        ExCortex.Ruminations.create_proposal(%{
          synapse_id: step.id,
          type: "roster_change",
          description: "Narrow roster",
          status: "pending"
        })

      Signals.sync_proposals()
      cards = Signals.list_signals(type: "proposal")
      assert length(cards) == 1
      assert hd(cards).metadata["proposal_id"] == proposal.id
    end

    test "does not duplicate cards for already-synced proposals" do
      {:ok, step} =
        ExCortex.Ruminations.create_synapse(%{name: "Sync Step 2", trigger: "manual", roster: []})

      {:ok, _} =
        ExCortex.Ruminations.create_proposal(%{
          synapse_id: step.id,
          type: "other",
          description: "Already here",
          status: "pending"
        })

      Signals.sync_proposals()
      Signals.sync_proposals()
      cards = Signals.list_signals(type: "proposal")
      assert length(cards) == 1
    end
  end

  describe "sync_augury/0" do
    test "creates an augury card from the memory entry tagged augury" do
      ExCortex.Memory.create_engram(%{
        title: "World Read",
        body: "Markets shifting",
        tags: ["augury"],
        source: "manual"
      })

      Signals.sync_augury()
      cards = Signals.list_signals(type: "augury")
      assert length(cards) == 1
      assert hd(cards).title == "World Read"
      assert hd(cards).pinned == true
    end

    test "updates existing augury card instead of creating duplicate" do
      ExCortex.Memory.create_engram(%{
        title: "First Read",
        body: "Initial",
        tags: ["augury"],
        source: "manual"
      })

      Signals.sync_augury()
      assert length(Signals.list_signals(type: "augury")) == 1

      ExCortex.Memory.create_engram(%{
        title: "Updated Read",
        body: "Revised",
        tags: ["augury"],
        source: "manual"
      })

      Signals.sync_augury()
      cards = Signals.list_signals(type: "augury")
      assert length(cards) == 1
    end

    test "does nothing when no augury entry exists" do
      assert Signals.sync_augury() == :noop
      assert Signals.list_signals(type: "augury") == []
    end
  end

  describe "upsert_card/1" do
    test "creates a new card when pin_slug does not exist" do
      assert {:ok, card} =
               Signals.upsert_signal(%{
                 type: "briefing",
                 card_type: "briefing",
                 title: "Test Card",
                 body: "Hello",
                 source: "thought",
                 pin_slug: "test-card",
                 pinned: true
               })

      assert card.pin_slug == "test-card"
      assert card.pinned == true
    end

    test "updates existing card when pin_slug matches, saving version" do
      {:ok, original} =
        Signals.upsert_signal(%{
          type: "briefing",
          card_type: "briefing",
          title: "V1",
          body: "Original body",
          source: "thought",
          pin_slug: "test-card",
          pinned: true
        })

      {:ok, updated} =
        Signals.upsert_signal(%{
          type: "briefing",
          card_type: "briefing",
          title: "V2",
          body: "Updated body",
          source: "thought",
          pin_slug: "test-card",
          pinned: true
        })

      assert updated.id == original.id
      assert updated.title == "V2"
      assert updated.body == "Updated body"

      versions = ExCortex.Repo.all(ExCortex.Signals.Version)
      assert length(versions) == 1
      assert hd(versions).body == "Original body"
    end

    test "creates card without pin_slug (no upsert)" do
      {:ok, c1} = Signals.upsert_signal(%{type: "note", title: "A", body: "", source: "manual"})
      {:ok, c2} = Signals.upsert_signal(%{type: "note", title: "B", body: "", source: "manual"})
      assert c1.id != c2.id
    end
  end

  describe "delete_card/1" do
    test "deletes a card" do
      {:ok, card} = Signals.create_signal(%{type: "note", title: "Delete me", source: "manual"})
      {:ok, _} = Signals.delete_signal(card)
      assert Signals.list_signals() == []
    end
  end
end
