defmodule ExCaliburWeb.GrimoireLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge

  alias ExCalibur.Lore
  alias ExCalibur.Quests
  alias ExCalibur.Settings
  alias ExCalibur.StepRunner

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) and is_nil(Settings.get_banner()) do
      {:ok, push_navigate(socket, to: ~p"/town-square")}
    else
      mount_grimoire(socket)
    end
  end

  defp mount_grimoire(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCalibur.PubSub, "lore")
      Phoenix.PubSub.subscribe(ExCalibur.PubSub, "source_activity")
    end

    {:ok,
     socket
     |> assign(
       page_title: "Grimoire",
       quests: Quests.list_quests(),
       filter_tags: [],
       filter_quest_id: nil,
       sort: "newest",
       editing_id: nil,
       intake_steps: Enum.filter(Quests.list_steps(), &(&1.status == "active")),
       running: false
     )
     |> reload()}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:quest_started, name, n}, socket) do
    label = if n == 1, do: "1 item", else: "#{n} items"
    {:noreply, put_flash(socket, :info, "Thinking... #{name} (#{label})")}
  end

  def handle_info({:quest_error, name, msg}, socket) do
    {:noreply, put_flash(socket, :error, "#{name} failed: #{msg}")}
  end

  def handle_info({:lore_updated, title}, socket) do
    {:noreply, socket |> reload() |> put_flash(:info, "New entry: #{title}")}
  end

  def handle_info({:drop_in_complete, step_run_id, result}, socket) do
    step_run = ExCalibur.Repo.get!(ExCalibur.Quests.StepRun, step_run_id)

    {status, results} =
      case result do
        {:ok, outcome} -> {"complete", outcome}
        {:error, reason} -> {"failed", %{error: inspect(reason)}}
      end

    Quests.update_step_run(step_run, %{status: status, results: results})
    socket = assign(socket, running: false)

    socket =
      if status == "complete",
        do: put_flash(socket, :info, "Processed — check below for the new entry."),
        else: put_flash(socket, :error, "Processing failed.")

    {:noreply, reload(socket)}
  end

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
    {:noreply, assign(socket, editing_id: :new)}
  end

  def handle_event("create_entry", %{"entry" => params}, socket) do
    attrs = parse_entry_params(params)

    case Lore.create_entry(Map.put(attrs, :source, "manual")) do
      {:ok, _} -> {:noreply, reload(assign(socket, editing_id: nil))}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to create entry")}
    end
  end

  def handle_event("cancel", _, socket) do
    {:noreply, assign(socket, editing_id: nil)}
  end

  def handle_event("edit_entry", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_id: String.to_integer(id))}
  end

  def handle_event("update_entry", %{"_id" => id, "entry" => params}, socket) do
    entry = Lore.get_entry!(String.to_integer(id))
    attrs = parse_entry_params(params)

    case Lore.update_entry(entry, attrs) do
      {:ok, _} -> {:noreply, reload(assign(socket, editing_id: nil))}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to update entry")}
    end
  end

  def handle_event("drop_in", %{"step_id" => step_id, "input" => input}, socket) when input != "" do
    step = Quests.get_step!(String.to_integer(step_id))
    {:ok, step_run} = Quests.create_step_run(%{step_id: step.id, input: input, status: "running"})
    parent = self()

    Task.start(fn ->
      result = StepRunner.run(step, input)
      send(parent, {:drop_in_complete, step_run.id, result})
    end)

    {:noreply, assign(socket, running: true)}
  end

  def handle_event("drop_in", _, socket) do
    {:noreply, put_flash(socket, :error, "Please enter something to process")}
  end

  def handle_event("delete_entry", %{"id" => id}, socket) do
    entry = Lore.get_entry!(String.to_integer(id))
    Lore.delete_entry(entry)
    {:noreply, reload(socket)}
  end

  defp reload(socket) do
    augury = [tags: ["augury"], sort: "newest"] |> Lore.list_entries() |> List.first()

    entries =
      [tags: socket.assigns.filter_tags, quest_id: socket.assigns.filter_quest_id, sort: socket.assigns.sort]
      |> Lore.list_entries()
      |> Enum.reject(&(augury && &1.id == augury.id))

    assign(socket, augury: augury, entries: entries)
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
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Grimoire</h1>
        <p class="text-muted-foreground mt-1.5">
          Synthesized artifacts and curated entries from your guild's quests.
        </p>
      </div>

      <%!-- Drop In form --%>
      <div class="rounded-lg border p-5 space-y-3 bg-card">
        <p class="text-sm font-semibold">Drop In</p>
        <p class="text-xs text-muted-foreground">
          Paste a link, note, thought, or doc. Choose how to process it and it'll land here.
        </p>
        <form phx-submit="drop_in" class="space-y-3">
          <textarea
            name="input"
            rows="3"
            placeholder="https://... or paste text, a note, anything"
            class="w-full text-sm border border-input rounded-md px-3 py-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
          ></textarea>
          <div class="flex gap-2 items-center">
            <select
              name="step_id"
              class="flex-1 h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
            >
              <%= for step <- @intake_steps do %>
                <option value={step.id}>{step.name}</option>
              <% end %>
            </select>
            <.button type="submit" size="sm" disabled={@running}>
              {if @running, do: "Processing…", else: "Process"}
            </.button>
          </div>
        </form>
      </div>

      <%!-- The Augury — pinned world thesis hero --%>
      <%= if @augury do %>
        <div class="rounded-xl border-2 border-primary/20 bg-primary/5 p-6 space-y-3">
          <div class="flex items-start justify-between gap-4">
            <div>
              <div class="flex items-center gap-2">
                <span class="text-xs font-semibold uppercase tracking-widest text-primary/60">
                  The Augury
                </span>
                <%= if @augury.importance do %>
                  <span class="text-xs text-muted-foreground font-mono">
                    {importance_dots(@augury.importance)}
                  </span>
                <% end %>
              </div>
              <h2 class="text-lg font-semibold mt-0.5">{@augury.title}</h2>
              <p class="text-xs text-muted-foreground mt-0.5">
                The guild's living read on the world — updated by the Strategist.
                Last revised {Calendar.strftime(@augury.updated_at, "%b %d at %H:%M")}.
              </p>
            </div>
            <div class="flex gap-2 shrink-0">
              <.button
                type="button"
                variant="outline"
                size="sm"
                phx-click="edit_entry"
                phx-value-id={@augury.id}
              >
                Edit
              </.button>
            </div>
          </div>
          <%= if @augury.body && @augury.body != "" do %>
            <div class="text-sm text-foreground/80 border-t border-primary/10 pt-3">
              <.md content={@augury.body} />
            </div>
          <% end %>
          <%= if @augury.tags != [] do %>
            <div class="flex flex-wrap gap-1 pt-1">
              <%= for tag <- @augury.tags do %>
                <.badge variant="outline" class="text-xs border-primary/20">{tag}</.badge>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

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
            type="button"
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
            type="button"
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
              <button type="button" phx-click="toggle_tag_filter" phx-value-tag={tag}>
                <.badge variant="default" class="text-xs cursor-pointer">{tag} ✕</.badge>
              </button>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Manual entry creation --%>
      <div class="flex justify-end">
        <.button type="button" variant="outline" size="sm" phx-click="add_entry">
          + Add Entry
        </.button>
      </div>

      <%= if @editing_id == :new do %>
        <.entry_form id="new-entry" submit_event="create_entry" entry={nil} />
      <% end %>

      <%!-- Entry feed --%>
      <%= if @entries == [] do %>
        <div class="rounded-lg border p-8 text-center">
          <p class="text-muted-foreground text-sm">
            No entries yet. Drop something in above or run an artifact quest.
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
                <button type="button" phx-click="toggle_tag_filter" phx-value-tag={tag}>
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
          <.button
            type="button"
            variant="outline"
            size="sm"
            phx-click="edit_entry"
            phx-value-id={@entry.id}
          >
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
        <div class="text-sm text-foreground/80 border-t pt-3">
          <.md content={@entry.body} />
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
