defmodule ExCaliburWeb.LodgeLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import ExCaliburWeb.Components.LodgeCards

  alias ExCalibur.Lodge
  alias ExCalibur.Quests.Proposal
  alias ExCalibur.Settings
  alias Excellence.Schemas.Member

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) and is_nil(Settings.get_banner()) do
      {:ok, push_navigate(socket, to: ~p"/town-square")}
    else
      mount_lodge(socket)
    end
  end

  defp mount_lodge(socket) do
    import Ecto.Query

    has_members =
      ExCalibur.Repo.exists?(from(r in Member, where: r.type == "role"))

    if has_members do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(ExCalibur.PubSub, "lodge")
      end

      Lodge.sync_proposals()
      {:ok, load_cards(assign(socket, page_title: "Lodge"))}
    else
      {:ok, push_navigate(socket, to: ~p"/town-square")}
    end
  end

  defp load_cards(socket) do
    cards = Lodge.list_cards()
    assign(socket, cards: cards)
  end

  @impl true
  def handle_info({:lodge_card_posted, _card}, socket) do
    {:noreply, load_cards(socket)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("create_card", %{"card" => params}, socket) do
    attrs = Map.put(params, "source", "manual")

    case Lodge.create_card(attrs) do
      {:ok, _} -> {:noreply, load_cards(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to create card")}
    end
  end

  @impl true
  def handle_event("dismiss_card", %{"card-id" => id}, socket) do
    card = Lodge.get_card!(id)
    Lodge.dismiss_card(card)
    {:noreply, load_cards(socket)}
  end

  @impl true
  def handle_event("delete_card", %{"card-id" => id}, socket) do
    card = Lodge.get_card!(id)
    Lodge.delete_card(card)
    {:noreply, load_cards(socket)}
  end

  @impl true
  def handle_event("toggle_pin", %{"card-id" => id}, socket) do
    card = Lodge.get_card!(id)
    Lodge.toggle_pin(card)
    {:noreply, load_cards(socket)}
  end

  @impl true
  def handle_event("toggle_checklist_item", %{"card-id" => id, "index" => idx}, socket) do
    card = Lodge.get_card!(id)
    Lodge.toggle_checklist_item(card, String.to_integer(idx))
    {:noreply, load_cards(socket)}
  end

  @impl true
  def handle_event("approve_proposal", %{"card-id" => id}, socket) do
    card = Lodge.get_card!(id)
    proposal_id = card.metadata["proposal_id"]

    if proposal_id do
      proposal = ExCalibur.Repo.get(Proposal, proposal_id)
      if proposal, do: ExCalibur.Quests.approve_proposal(proposal)
    end

    Lodge.dismiss_card(card)
    {:noreply, load_cards(socket)}
  end

  @impl true
  def handle_event("edit_augury", %{"card-id" => _id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("archive_card", %{"card-id" => id}, socket) do
    card = Lodge.get_card!(id)
    Lodge.update_card(card, %{status: "archived"})
    {:noreply, load_cards(socket)}
  end

  @impl true
  def handle_event("reject_proposal", %{"card-id" => id}, socket) do
    card = Lodge.get_card!(id)
    proposal_id = card.metadata["proposal_id"]

    if proposal_id do
      proposal = ExCalibur.Repo.get(Proposal, proposal_id)
      if proposal, do: ExCalibur.Quests.reject_proposal(proposal)
    end

    Lodge.dismiss_card(card)
    {:noreply, load_cards(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Lodge</h1>
        <p class="text-muted-foreground mt-1.5">
          Your guild's bulletin board — notes, checklists, alerts, and quest output.
        </p>
      </div>

      <div class="rounded-lg border border-dashed p-4">
        <form phx-submit="create_card" class="flex flex-col gap-3 sm:flex-row sm:items-end">
          <div class="flex-1 space-y-2">
            <div class="flex gap-2">
              <select
                name="card[type]"
                class="h-9 text-sm border border-input rounded-md px-3 bg-background"
              >
                <option value="note">Note</option>
                <option value="checklist">Checklist</option>
                <option value="meeting">Meeting</option>
                <option value="alert">Alert</option>
                <option value="link">Link</option>
              </select>
              <input
                type="text"
                name="card[title]"
                placeholder="Title"
                required
                class="flex-1 h-9 text-sm border border-input rounded-md px-3 bg-background"
              />
            </div>
            <textarea
              name="card[body]"
              rows="2"
              placeholder="Body (markdown)"
              class="w-full text-sm border border-input rounded-md px-3 py-2 bg-background"
            ></textarea>
          </div>
          <.button type="submit" size="sm">+ Add Card</.button>
        </form>
      </div>

      <%= if @cards == [] do %>
        <div class="rounded-lg border p-8 text-center">
          <p class="text-muted-foreground text-sm">
            No cards yet. Add one above or run a quest that posts to the Lodge.
          </p>
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for card <- @cards do %>
            <.lodge_card card={card} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
