defmodule ExCalibur.LodgeTest do
  use ExCalibur.DataCase

  alias ExCalibur.Lodge

  describe "list_cards/1" do
    test "returns active cards ordered by pinned desc, inserted_at desc" do
      {:ok, pinned} = Lodge.create_card(%{type: "note", title: "Pinned", source: "manual", pinned: true})
      {:ok, _recent} = Lodge.create_card(%{type: "note", title: "Recent", source: "manual"})
      {:ok, _dismissed} = Lodge.create_card(%{type: "note", title: "Gone", source: "manual", status: "dismissed"})

      cards = Lodge.list_cards()
      assert length(cards) == 2
      assert hd(cards).id == pinned.id
    end

    test "filters by type" do
      {:ok, _} = Lodge.create_card(%{type: "note", title: "A", source: "manual"})
      {:ok, _} = Lodge.create_card(%{type: "alert", title: "B", source: "manual"})

      cards = Lodge.list_cards(type: "note")
      assert length(cards) == 1
      assert hd(cards).type == "note"
    end

    test "filters by tags" do
      {:ok, _} = Lodge.create_card(%{type: "note", title: "Tagged", source: "manual", tags: ["tech", "urgent"]})
      {:ok, _} = Lodge.create_card(%{type: "note", title: "Other", source: "manual", tags: ["idea"]})
      {:ok, _} = Lodge.create_card(%{type: "note", title: "None", source: "manual"})

      cards = Lodge.list_cards(tags: ["tech"])
      assert length(cards) == 1
      assert hd(cards).title == "Tagged"

      cards = Lodge.list_cards(tags: ["tech", "idea"])
      assert length(cards) == 2
    end
  end

  describe "create_card/1" do
    test "creates a card" do
      {:ok, card} = Lodge.create_card(%{type: "note", title: "Hello", body: "world", source: "manual"})
      assert card.id
      assert card.type == "note"
      assert card.status == "active"
    end
  end

  describe "update_card/2" do
    test "updates a card" do
      {:ok, card} = Lodge.create_card(%{type: "note", title: "Old", source: "manual"})
      {:ok, updated} = Lodge.update_card(card, %{title: "New"})
      assert updated.title == "New"
    end
  end

  describe "dismiss_card/1" do
    test "sets status to dismissed" do
      {:ok, card} = Lodge.create_card(%{type: "note", title: "Bye", source: "manual"})
      {:ok, dismissed} = Lodge.dismiss_card(card)
      assert dismissed.status == "dismissed"
    end
  end

  describe "toggle_pin/1" do
    test "toggles pinned state" do
      {:ok, card} = Lodge.create_card(%{type: "note", title: "Pin me", source: "manual"})
      refute card.pinned
      {:ok, pinned} = Lodge.toggle_pin(card)
      assert pinned.pinned
      {:ok, unpinned} = Lodge.toggle_pin(pinned)
      refute unpinned.pinned
    end
  end

  describe "post_card/1" do
    test "creates a card and broadcasts" do
      Phoenix.PubSub.subscribe(ExCalibur.PubSub, "lodge")
      {:ok, card} = Lodge.post_card(%{type: "alert", title: "Urgent", source: "quest"})
      assert card.id
      assert_receive {:lodge_card_posted, ^card}
    end
  end

  describe "toggle_checklist_item/3" do
    test "toggles a checklist item" do
      {:ok, card} =
        Lodge.create_card(%{
          type: "checklist",
          title: "TODO",
          source: "manual",
          metadata: %{"items" => [%{"text" => "A", "checked" => false}, %{"text" => "B", "checked" => true}]}
        })

      {:ok, updated} = Lodge.toggle_checklist_item(card, 0)
      assert Enum.at(updated.metadata["items"], 0)["checked"] == true
      assert Enum.at(updated.metadata["items"], 1)["checked"] == true
    end
  end

  describe "sync_proposals/0" do
    test "creates cards for pending proposals that don't have cards yet" do
      {:ok, step} =
        ExCalibur.Quests.create_step(%{name: "Sync Step", trigger: "manual", roster: []})

      {:ok, proposal} =
        ExCalibur.Quests.create_proposal(%{
          quest_id: step.id,
          type: "roster_change",
          description: "Narrow roster",
          status: "pending"
        })

      Lodge.sync_proposals()
      cards = Lodge.list_cards(type: "proposal")
      assert length(cards) == 1
      assert hd(cards).metadata["proposal_id"] == proposal.id
    end

    test "does not duplicate cards for already-synced proposals" do
      {:ok, step} =
        ExCalibur.Quests.create_step(%{name: "Sync Step 2", trigger: "manual", roster: []})

      {:ok, _} =
        ExCalibur.Quests.create_proposal(%{
          quest_id: step.id,
          type: "other",
          description: "Already here",
          status: "pending"
        })

      Lodge.sync_proposals()
      Lodge.sync_proposals()
      cards = Lodge.list_cards(type: "proposal")
      assert length(cards) == 1
    end
  end

  describe "sync_augury/0" do
    test "creates an augury card from the lore entry tagged augury" do
      ExCalibur.Lore.create_entry(%{
        title: "World Read",
        body: "Markets shifting",
        tags: ["augury"],
        source: "manual"
      })

      Lodge.sync_augury()
      cards = Lodge.list_cards(type: "augury")
      assert length(cards) == 1
      assert hd(cards).title == "World Read"
      assert hd(cards).pinned == true
    end

    test "updates existing augury card instead of creating duplicate" do
      ExCalibur.Lore.create_entry(%{
        title: "First Read",
        body: "Initial",
        tags: ["augury"],
        source: "manual"
      })

      Lodge.sync_augury()
      assert length(Lodge.list_cards(type: "augury")) == 1

      ExCalibur.Lore.create_entry(%{
        title: "Updated Read",
        body: "Revised",
        tags: ["augury"],
        source: "manual"
      })

      Lodge.sync_augury()
      cards = Lodge.list_cards(type: "augury")
      assert length(cards) == 1
    end

    test "does nothing when no augury entry exists" do
      assert Lodge.sync_augury() == :noop
      assert Lodge.list_cards(type: "augury") == []
    end
  end

  describe "upsert_card/1" do
    test "creates a new card when pin_slug does not exist" do
      assert {:ok, card} =
               Lodge.upsert_card(%{
                 type: "briefing",
                 card_type: "briefing",
                 title: "Test Card",
                 body: "Hello",
                 source: "quest",
                 pin_slug: "test-card",
                 pinned: true
               })

      assert card.pin_slug == "test-card"
      assert card.pinned == true
    end

    test "updates existing card when pin_slug matches, saving version" do
      {:ok, original} =
        Lodge.upsert_card(%{
          type: "briefing",
          card_type: "briefing",
          title: "V1",
          body: "Original body",
          source: "quest",
          pin_slug: "test-card",
          pinned: true
        })

      {:ok, updated} =
        Lodge.upsert_card(%{
          type: "briefing",
          card_type: "briefing",
          title: "V2",
          body: "Updated body",
          source: "quest",
          pin_slug: "test-card",
          pinned: true
        })

      assert updated.id == original.id
      assert updated.title == "V2"
      assert updated.body == "Updated body"

      versions = ExCalibur.Repo.all(ExCalibur.Lodge.CardVersion)
      assert length(versions) == 1
      assert hd(versions).body == "Original body"
    end

    test "creates card without pin_slug (no upsert)" do
      {:ok, c1} = Lodge.upsert_card(%{type: "note", title: "A", body: "", source: "manual"})
      {:ok, c2} = Lodge.upsert_card(%{type: "note", title: "B", body: "", source: "manual"})
      assert c1.id != c2.id
    end
  end

  describe "delete_card/1" do
    test "deletes a card" do
      {:ok, card} = Lodge.create_card(%{type: "note", title: "Delete me", source: "manual"})
      {:ok, _} = Lodge.delete_card(card)
      assert Lodge.list_cards() == []
    end
  end
end
