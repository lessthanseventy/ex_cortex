defmodule ExCaliburWeb.GrimoireLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge

  alias ExCalibur.Lore
  alias ExCalibur.Quests

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCalibur.PubSub, "lore")
    end

    {:ok,
     assign(socket,
       page_title: "Grimoire",
       entries: Lore.list_entries(),
       quests: Quests.list_quests(),
       filter_tags: [],
       filter_quest_id: nil,
       sort: "newest",
       adding: false,
       editing_id: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_msg, socket), do: {:noreply, reload(socket)}

  @impl true
  def handle_event("toggle_tag_filter", %{"tag" => tag}, socket) do
    tags =
      if tag in socket.assigns.filter_tags,
        do: List.delete(socket.assigns.filter_tags, tag),
        else: [tag | socket.assigns.filter_tags]

    {:noreply, reload(assign(socket, filter_tags: tags))}
  end

  def handle_event("filter_quest", %{"quest_id" => ""}, socket) do
    {:noreply, reload(assign(socket, filter_quest_id: nil))}
  end

  def handle_event("filter_quest", %{"quest_id" => id}, socket) do
    {:noreply, reload(assign(socket, filter_quest_id: String.to_integer(id)))}
  end

  def handle_event("set_sort", %{"sort" => sort}, socket) do
    {:noreply, reload(assign(socket, sort: sort))}
  end

  def handle_event("add_entry", _, socket) do
    {:noreply, assign(socket, adding: true, editing_id: nil)}
  end

  def handle_event("cancel", _, socket) do
    {:noreply, assign(socket, adding: false, editing_id: nil)}
  end

  def handle_event("create_entry", %{"entry" => params}, socket) do
    attrs = parse_entry_params(params) |> Map.put(:source, "manual")

    case Lore.create_entry(attrs) do
      {:ok, _} -> {:noreply, reload(assign(socket, adding: false))}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to create entry")}
    end
  end

  def handle_event("edit_entry", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_id: String.to_integer(id), adding: false)}
  end

  def handle_event("update_entry", %{"_id" => id, "entry" => params}, socket) do
    entry = Lore.get_entry!(String.to_integer(id))
    attrs = parse_entry_params(params) |> Map.put(:source, "manual")

    case Lore.update_entry(entry, attrs) do
      {:ok, _} -> {:noreply, reload(assign(socket, editing_id: nil))}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to update entry")}
    end
  end

  def handle_event("delete_entry", %{"id" => id}, socket) do
    entry = Lore.get_entry!(String.to_integer(id))
    Lore.delete_entry(entry)
    {:noreply, reload(socket)}
  end

  defp reload(socket) do
    entries =
      Lore.list_entries(
        tags: socket.assigns.filter_tags,
        quest_id: socket.assigns.filter_quest_id,
        sort: socket.assigns.sort
      )

    assign(socket, entries: entries)
  end

  defp parse_entry_params(params) do
    tags =
      (params["tags"] || "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    importance =
      case Integer.parse(params["importance"] || "") do
        {n, ""} when n in 1..5 -> n
        _ -> nil
      end

    %{
      title: params["title"] || "",
      body: params["body"] || "",
      tags: tags,
      importance: importance
    }
  end

  defp quest_name(quests, quest_id) when is_integer(quest_id) do
    case Enum.find(quests, &(&1.id == quest_id)) do
      nil -> "Quest ##{quest_id}"
      quest -> quest.name
    end
  end

  defp importance_dots(nil), do: "○○○○○"

  defp importance_dots(n) do
    String.duplicate("●", n) <> String.duplicate("○", 5 - n)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 class="text-3xl font-bold tracking-tight">Grimoire</h1>
          <p class="text-muted-foreground mt-1.5">
            Synthesized artifacts and curated entries from your guild's quests.
          </p>
        </div>
        <.button variant="outline" phx-click="add_entry" class="self-start sm:mt-1">
          + New Entry
        </.button>
      </div>

      <%!-- Filter bar --%>
      <div class="flex flex-wrap items-center gap-3">
        <select
          phx-change="filter_quest"
          name="quest_id"
          class="h-8 text-sm border border-input rounded-md px-2 bg-background focus:outline-none"
        >
          <option value="">All quests</option>
          <%= for quest <- @quests do %>
            <option value={quest.id} selected={@filter_quest_id == quest.id}>{quest.name}</option>
          <% end %>
        </select>
        <div class="flex gap-1">
          <button
            phx-click="set_sort"
            phx-value-sort="newest"
            class={[
              "px-3 py-1 text-xs rounded-md border transition-colors",
              if(@sort == "newest",
                do: "bg-accent text-foreground border-accent",
                else: "border-border text-muted-foreground hover:bg-muted"
              )
            ]}
          >
            Newest
          </button>
          <button
            phx-click="set_sort"
            phx-value-sort="importance"
            class={[
              "px-3 py-1 text-xs rounded-md border transition-colors",
              if(@sort == "importance",
                do: "bg-accent text-foreground border-accent",
                else: "border-border text-muted-foreground hover:bg-muted"
              )
            ]}
          >
            Importance
          </button>
        </div>
        <%= if @filter_tags != [] do %>
          <div class="flex flex-wrap gap-1 items-center">
            <span class="text-xs text-muted-foreground">Filtered:</span>
            <%= for tag <- @filter_tags do %>
              <button phx-click="toggle_tag_filter" phx-value-tag={tag}>
                <.badge variant="default" class="text-xs cursor-pointer">{tag} ✕</.badge>
              </button>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- New entry form --%>
      <%= if @adding do %>
        <.entry_form id="new-entry" submit_event="create_entry" entry={nil} />
      <% end %>

      <%!-- Entry feed --%>
      <%= if @entries == [] do %>
        <div class="rounded-lg border p-8 text-center">
          <p class="text-muted-foreground text-sm">
            No entries yet. Create one manually or run an artifact quest.
          </p>
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for entry <- @entries do %>
            <%= if @editing_id == entry.id do %>
              <.entry_form id={"edit-#{entry.id}"} submit_event="update_entry" entry={entry} />
            <% else %>
              <.entry_card
                entry={entry}
                quest_name={if entry.quest_id, do: quest_name(@quests, entry.quest_id), else: nil}
                active_tags={@filter_tags}
              />
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :quest_name, :string, default: nil
  attr :active_tags, :list, default: []

  defp entry_card(assigns) do
    ~H"""
    <div class="rounded-lg border bg-card p-5 space-y-3">
      <div class="flex items-start justify-between gap-3">
        <div class="space-y-1 flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <span class="font-medium truncate">{@entry.title}</span>
            <%= if @entry.importance do %>
              <span class="text-xs text-muted-foreground font-mono shrink-0">
                {importance_dots(@entry.importance)}
              </span>
            <% end %>
            <%= if @entry.source == "manual" do %>
              <span class="text-xs text-muted-foreground shrink-0" title="Manually curated">✎</span>
            <% end %>
          </div>
          <%= if @entry.tags != [] do %>
            <div class="flex flex-wrap gap-1">
              <%= for tag <- @entry.tags do %>
                <button phx-click="toggle_tag_filter" phx-value-tag={tag}>
                  <.badge
                    variant={if tag in @active_tags, do: "default", else: "outline"}
                    class="text-xs cursor-pointer"
                  >
                    {tag}
                  </.badge>
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
        <div class="flex gap-2 shrink-0">
          <.button variant="outline" size="sm" phx-click="edit_entry" phx-value-id={@entry.id}>
            Edit
          </.button>
          <.button
            variant="destructive"
            size="sm"
            phx-click="delete_entry"
            phx-value-id={@entry.id}
            data-confirm={
              if @entry.source == "quest",
                do:
                  "This entry will be re-generated on the next quest run unless you change the quest's write mode.",
                else: "Delete this entry?"
            }
          >
            ✕
          </.button>
        </div>
      </div>
      <%= if @entry.body && @entry.body != "" do %>
        <div class="text-sm text-foreground/80 whitespace-pre-wrap border-t pt-3">
          {@entry.body}
        </div>
      <% end %>
      <div class="text-xs text-muted-foreground border-t pt-2 flex items-center gap-2">
        <%= if @quest_name do %>
          <span>From: {@quest_name}</span>
          <span>·</span>
        <% else %>
          <span>Manual</span>
          <span>·</span>
        <% end %>
        <span>
          <%= if @entry.source == "quest" and @entry.inserted_at != @entry.updated_at do %>
            Last updated {Calendar.strftime(@entry.updated_at, "%b %d %H:%M")}
          <% else %>
            {Calendar.strftime(@entry.inserted_at, "%b %d %H:%M")}
          <% end %>
        </span>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :submit_event, :string, required: true
  attr :entry, :any, required: true

  defp entry_form(assigns) do
    ~H"""
    <div class="rounded-lg border border-dashed p-5">
      <form phx-submit={@submit_event} class="space-y-3">
        <%= if @entry do %>
          <input type="hidden" name="_id" value={@entry.id} />
        <% end %>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <label class="text-sm font-medium">Title</label>
            <input
              type="text"
              name="entry[title]"
              value={if @entry, do: @entry.title, else: ""}
              placeholder="Entry title"
              class="mt-1 w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
            />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-sm font-medium">Importance</label>
              <select
                name="entry[importance]"
                class="mt-1 w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
              >
                <option value="">None</option>
                <%= for n <- 1..5 do %>
                  <option value={n} selected={@entry && @entry.importance == n}>{n}</option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="text-sm font-medium">Tags</label>
              <input
                type="text"
                name="entry[tags]"
                value={if @entry, do: Enum.join(@entry.tags, ", "), else: ""}
                placeholder="a11y, security"
                class="mt-1 w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
              />
            </div>
          </div>
        </div>
        <div>
          <label class="text-sm font-medium">Body (markdown)</label>
          <textarea
            name="entry[body]"
            rows="4"
            placeholder="Content…"
            class="mt-1 w-full text-sm border border-input rounded-md px-3 py-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
          >{if @entry, do: @entry.body, else: ""}</textarea>
        </div>
        <div class="flex justify-end gap-2">
          <.button type="button" variant="outline" size="sm" phx-click="cancel">Cancel</.button>
          <.button type="submit" size="sm">
            {if @entry, do: "Save changes", else: "Create Entry"}
          </.button>
        </div>
      </form>
    </div>
    """
  end
end
