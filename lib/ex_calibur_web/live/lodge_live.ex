defmodule ExCaliburWeb.LodgeLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import Ecto.Query, only: [from: 2]
  import ExCaliburWeb.Components.LodgeCards

  alias ExCalibur.Lodge
  alias ExCalibur.Quests.Proposal
  alias ExCalibur.Quests.Quest
  alias ExCalibur.Quests.QuestRun
  alias ExCalibur.Repo
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
      Repo.exists?(from(r in Member, where: r.type == "role"))

    if has_members do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(ExCalibur.PubSub, "lodge")
        Phoenix.PubSub.subscribe(ExCalibur.PubSub, "lore")
        Lodge.sync_proposals()
        Lodge.sync_augury()
      end

      {:ok,
       load_cards(
         assign(socket,
           page_title: "Lodge",
           selected_tags: [],
           filter_tags: [],
           dev_team_status: load_dev_team_status()
         )
       )}
    else
      {:ok, push_navigate(socket, to: ~p"/town-square")}
    end
  end

  defp load_cards(socket) do
    opts =
      case socket.assigns[:filter_tags] do
        [] -> []
        nil -> []
        tags -> [tags: tags]
      end

    cards = Lodge.list_cards(opts)
    pinned = Enum.filter(cards, & &1.pinned)
    feed = Enum.reject(cards, & &1.pinned)
    assign(socket, cards: cards, pinned_cards: pinned, feed_cards: feed)
  end

  @impl true
  def handle_info({:lodge_card_posted, _card}, socket) do
    {:noreply, load_cards(socket)}
  end

  @impl true
  def handle_info({:lore_updated, _title}, socket) do
    Lodge.sync_augury()
    {:noreply, load_cards(socket)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("create_card", %{"card" => params}, socket) do
    tags = socket.assigns.selected_tags
    custom = params["custom_tag"] || ""

    all_tags =
      if custom == "" do
        tags
      else
        custom
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.concat(tags)
        |> Enum.uniq()
      end

    attrs =
      params
      |> Map.put("source", "manual")
      |> Map.put("tags", all_tags)
      |> Map.delete("custom_tag")

    case Lodge.create_card(attrs) do
      {:ok, _} -> {:noreply, load_cards(assign(socket, selected_tags: []))}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to create card")}
    end
  end

  @impl true
  def handle_event("toggle_tag", %{"tag" => tag}, socket) do
    tags = socket.assigns.selected_tags

    updated =
      if tag in tags do
        List.delete(tags, tag)
      else
        [tag | tags]
      end

    {:noreply, assign(socket, selected_tags: updated)}
  end

  @impl true
  def handle_event("toggle_filter_tag", %{"tag" => ""}, socket) do
    {:noreply, load_cards(assign(socket, filter_tags: []))}
  end

  def handle_event("toggle_filter_tag", %{"tag" => tag}, socket) do
    tags = socket.assigns.filter_tags

    updated =
      if tag in tags do
        List.delete(tags, tag)
      else
        [tag | tags]
      end

    {:noreply, load_cards(assign(socket, filter_tags: updated))}
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
  def handle_event("action_list_approve", %{"card-id" => id, "item-id" => item_id}, socket) do
    update_action_list_item(id, item_id, "approved")
    {:noreply, load_cards(socket)}
  end

  @impl true
  def handle_event("action_list_reject", %{"card-id" => id, "item-id" => item_id}, socket) do
    update_action_list_item(id, item_id, "rejected")
    {:noreply, load_cards(socket)}
  end

  @impl true
  def handle_event("approve_proposal", %{"card-id" => id}, socket) do
    card = Lodge.get_card!(id)
    maybe_approve_proposal(card.metadata["proposal_id"])
    Lodge.dismiss_card(card)
    {:noreply, load_cards(socket)}
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
      proposal = Repo.get(Proposal, proposal_id)
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
          Your guild's dashboard — pinned cards, quest output, and notes.
        </p>
        <p class="text-sm text-muted-foreground">
          {length(@cards)} cards · {length(@pinned_cards)} pinned
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
                <option value="briefing">Briefing</option>
                <option value="note">Note</option>
                <option value="checklist">Checklist</option>
                <option value="table">Table</option>
                <option value="metric">Metric</option>
                <option value="freeform">Freeform</option>
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
            <div class="flex items-center gap-2 flex-wrap">
              <span class="text-xs text-muted-foreground">Tags:</span>
              <%= for tag <- ExCaliburWeb.Components.LodgeCards.preset_tags() do %>
                <button
                  type="button"
                  phx-click="toggle_tag"
                  phx-value-tag={tag}
                  class={"inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium cursor-pointer transition-colors " <> if(tag in @selected_tags, do: "bg-primary text-primary-foreground", else: "bg-muted text-muted-foreground hover:bg-muted/80")}
                >
                  {tag}
                </button>
              <% end %>
              <input
                type="text"
                name="card[custom_tag]"
                placeholder="custom tag"
                class="h-7 w-28 text-xs border border-input rounded-full px-2.5 bg-background"
              />
            </div>
          </div>
          <.button type="submit" size="sm">+ Add Card</.button>
        </form>
      </div>

      <div class="flex items-center gap-2 flex-wrap">
        <span class="text-xs font-medium text-muted-foreground">Filter:</span>
        <%= for tag <- ExCaliburWeb.Components.LodgeCards.preset_tags() do %>
          <button
            type="button"
            phx-click="toggle_filter_tag"
            phx-value-tag={tag}
            class={"inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium cursor-pointer transition-colors " <> if(tag in @filter_tags, do: "bg-primary text-primary-foreground", else: "bg-muted text-muted-foreground hover:bg-muted/80")}
          >
            {tag}
          </button>
        <% end %>
        <%= if @filter_tags != [] do %>
          <button
            type="button"
            phx-click="toggle_filter_tag"
            phx-value-tag=""
            class="text-xs text-muted-foreground hover:text-foreground underline"
          >
            clear
          </button>
        <% end %>
      </div>

      <%!-- Dev Team Status --%>
      <%= if @dev_team_status != [] do %>
        <div class="rounded-lg border bg-muted/30 px-4 py-3">
          <div class="flex items-center gap-2 flex-wrap">
            <span class="text-xs font-medium text-muted-foreground uppercase tracking-wide mr-1">
              Dev Team
            </span>
            <%= for entry <- @dev_team_status do %>
              <div class="flex items-center gap-1.5 text-xs rounded-full border bg-background px-2.5 py-1">
                <span class={[
                  "h-1.5 w-1.5 rounded-full",
                  entry.last_run == nil && "bg-muted",
                  entry.last_run && entry.last_run.status == "complete" && "bg-green-500",
                  entry.last_run && entry.last_run.status == "failed" && "bg-red-500",
                  entry.last_run && entry.last_run.status == "running" && "bg-amber-400 animate-pulse"
                ]}>
                </span>
                <span class="font-medium">{entry.quest.name}</span>
                <span class="text-muted-foreground">
                  {format_lodge_time(entry.last_run && entry.last_run.inserted_at)}
                </span>
                <%= if entry.artifact_count > 0 do %>
                  <span class="text-primary">· {entry.artifact_count} filed</span>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- Pinned Cards Grid --%>
      <%= if @pinned_cards != [] do %>
        <div>
          <h2 class="text-sm font-medium text-muted-foreground mb-3">Pinned</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= for card <- @pinned_cards do %>
              <div class={card_grid_class(card)}>
                <.lodge_card card={card} />
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- Feed --%>
      <div>
        <%= if @pinned_cards != [] do %>
          <h2 class="text-sm font-medium text-muted-foreground mb-3">Recent</h2>
        <% end %>
        <%= if @feed_cards == [] and @pinned_cards == [] do %>
          <div class="rounded-lg border p-8 text-center">
            <p class="text-muted-foreground text-sm">
              No cards yet. Cards appear here when quests run, or you can create one above.
            </p>
            <p class="text-xs text-muted-foreground mt-2">
              Set up quests from the <a href="/quests" class="underline text-primary">Quests</a> page.
            </p>
          </div>
        <% else %>
          <div class="space-y-4">
            <%= for card <- @feed_cards do %>
              <.lodge_card card={card} />
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp maybe_approve_proposal(nil), do: :ok

  defp maybe_approve_proposal(proposal_id) do
    proposal = Repo.get(Proposal, proposal_id)

    if proposal do
      ExCalibur.Quests.approve_proposal(proposal)

      if proposal.type == "tool_action" do
        ExCalibur.Quests.execute_tool_proposal(proposal)
      end
    end
  end

  defp update_action_list_item(card_id, item_id, status) do
    card = Lodge.get_card!(card_id)
    items = card.metadata["items"] || []

    updated_items =
      Enum.map(items, fn item ->
        if item["id"] == item_id, do: Map.put(item, "status", status), else: item
      end)

    Lodge.update_card(card, %{metadata: Map.put(card.metadata, "items", updated_items)})
  end

  defp load_dev_team_status do
    quests =
      Repo.all(
        from q in Quest,
          where: q.name in ["Daily Dev Triage", "Analyze Usage"],
          order_by: q.name
      )

    quest_ids = Enum.map(quests, & &1.id)

    last_runs =
      from(r in QuestRun,
        where: r.quest_id in ^quest_ids,
        order_by: [desc: r.inserted_at]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.quest_id)
      |> Map.new(fn {id, [latest | _]} -> {id, latest} end)

    Enum.map(quests, fn q ->
      run = Map.get(last_runs, q.id)
      %{quest: q, last_run: run, artifact_count: count_run_artifacts(run)}
    end)
  end

  defp count_run_artifacts(nil), do: 0

  defp count_run_artifacts(run) do
    run.step_results
    |> Map.values()
    |> Enum.flat_map(&Map.get(&1, "tool_calls", []))
    |> Enum.count(fn call -> call["tool"] in ["create_github_issue", "open_pr"] end)
  end

  defp format_lodge_time(nil), do: "never"

  defp format_lodge_time(dt) do
    diff = NaiveDateTime.diff(NaiveDateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp card_grid_class(%{type: "metric"}), do: "col-span-1"

  defp card_grid_class(%{type: type}) when type in ~w(briefing table), do: "md:col-span-2 lg:col-span-2"

  defp card_grid_class(%{type: "action_list"}), do: "col-span-1 md:col-span-2 lg:col-span-3"
  defp card_grid_class(_), do: "col-span-1"
end
