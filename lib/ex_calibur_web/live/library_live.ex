defmodule ExCaliburWeb.LibraryLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge

  alias ExCalibur.Heralds.Herald
  alias ExCalibur.Library
  alias ExCalibur.Settings
  alias ExCalibur.Sources.Book
  alias ExCalibur.Sources.Source
  alias ExCalibur.Sources.SourceSupervisor
  alias ExCalibur.Sources.SourceWorker

  # Reference :dictionaries atom so String.to_existing_atom("dictionaries") works
  @valid_tabs [:scrolls, :books, :heralds, :dictionaries]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) and is_nil(Settings.get_banner()) do
      {:ok, push_navigate(socket, to: ~p"/town-square")}
    else
      mount_library(socket)
    end
  end

  defp mount_library(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCalibur.PubSub, "sources")
      Phoenix.PubSub.subscribe(ExCalibur.PubSub, "source_activity")
      Phoenix.PubSub.subscribe(ExCalibur.PubSub, "lore")
      :timer.send_interval(10_000, self(), :refresh)
    end

    socket =
      allow_upload(socket, :dictionary_file,
        accept: ~w(.txt .md .csv .json),
        max_entries: 1,
        max_file_size: 5_000_000
      )

    {:ok,
     load_data(
       assign(socket,
         page_title: "Library",
         tab: :scrolls,
         expanding: nil,
         herald_type_preview: "slack",
         editing_herald: nil,
         syncing: false,
         editing_dictionary: nil
       )
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load_data(socket)}
  def handle_info(:sync_done, socket), do: {:noreply, assign(socket, syncing: false)}

  def handle_info({:quest_started, name, n}, socket) do
    label = if n == 1, do: "1 item", else: "#{n} items"
    {:noreply, put_flash(socket, :info, "Thinking... #{name} (#{label})")}
  end

  def handle_info({:quest_error, name, msg}, socket) do
    {:noreply, put_flash(socket, :error, "#{name} failed: #{msg}")}
  end

  def handle_info({:lore_updated, title}, socket) do
    {:noreply, put_flash(socket, :info, "New entry: #{title}")}
  end

  def handle_info(_msg, socket), do: {:noreply, load_data(socket)}

  defp broadcast_sources do
    Phoenix.PubSub.broadcast(ExCalibur.PubSub, "sources", :refresh)
  end

  defp load_data(socket) do
    import Ecto.Query

    banner = Settings.get_banner()
    banner_atom = if banner, do: String.to_existing_atom(banner)

    sources = ExCalibur.Repo.all(from(s in Source, order_by: [desc: s.inserted_at]))
    stacked_ids = MapSet.new(sources, & &1.book_id)

    scroll_groups =
      Book.scrolls()
      |> filter_by_banner(banner_atom)
      |> Enum.reject(&MapSet.member?(stacked_ids, &1.id))
      |> group_by_guild()

    book_groups =
      Book.books()
      |> filter_by_banner(banner_atom)
      |> Enum.reject(&MapSet.member?(stacked_ids, &1.id))
      |> group_by_guild()

    heralds = ExCalibur.Heralds.list_heralds()
    dictionaries = Library.list_dictionaries()

    assign(socket,
      sources: sources,
      scroll_groups: scroll_groups,
      book_groups: book_groups,
      heralds: heralds,
      dictionaries: dictionaries
    )
  end

  defp filter_by_banner(items, nil), do: items

  defp filter_by_banner(items, banner_atom) do
    Enum.filter(items, &(&1.banner == banner_atom || &1.banner == nil))
  end

  defp group_by_guild(items) do
    items
    |> Enum.group_by(&(&1.suggested_guild || "General"))
    |> Enum.sort_by(fn {guild, _} -> if guild == "General", do: "zzz", else: guild end)
  end

  defp source_name(%Source{book_id: book_id}) when is_binary(book_id) do
    case Book.get(book_id) do
      nil -> book_id
      book -> book.name
    end
  end

  defp source_name(%Source{source_type: type}), do: String.capitalize(type) <> " source"

  defp format_time(nil), do: "Never"
  defp format_time(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  # ── Events ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("sync", %{"id" => id}, socket) do
    SourceWorker.sync(id)
    {:noreply, put_flash(socket, :info, "Syncing...")}
  end

  def handle_event("sync_all", _params, %{assigns: %{syncing: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("sync_all", _params, socket) do
    active = Enum.filter(socket.assigns.sources, &(&1.status == "active"))
    Enum.each(active, fn source -> SourceWorker.sync(source.id) end)
    n = length(active)
    Process.send_after(self(), :sync_done, 15_000)

    {:noreply,
     socket |> assign(syncing: true) |> put_flash(:info, "Syncing #{n} source#{if n == 1, do: "", else: "s"}...")}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    valid_tab = if tab in Enum.map(@valid_tabs, &to_string/1), do: String.to_existing_atom(tab), else: :scrolls
    {:noreply, assign(socket, tab: valid_tab, expanding: nil)}
  end

  @impl true
  def handle_event("create_dictionary", %{"dictionary" => params}, socket) do
    attrs = %{
      name: params["name"],
      description: params["description"],
      content: params["content"] || "",
      content_type: params["content_type"] || "text",
      tags: parse_tags(params["tags"] || "")
    }

    case Library.create_dictionary(attrs) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Dictionary created.") |> load_data()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to create dictionary.")}
    end
  end

  @impl true
  def handle_event("delete_dictionary", %{"id" => id}, socket) do
    dict = Library.get_dictionary!(String.to_integer(id))
    Library.delete_dictionary(dict)
    {:noreply, socket |> put_flash(:info, "Dictionary deleted.") |> load_data()}
  end

  @impl true
  def handle_event("edit_dictionary", %{"id" => id}, socket) do
    editing = if socket.assigns.editing_dictionary == id, do: nil, else: id
    {:noreply, assign(socket, editing_dictionary: editing)}
  end

  @impl true
  def handle_event("update_dictionary", %{"dictionary" => params, "_dictionary_id" => id}, socket) do
    dict = Library.get_dictionary!(String.to_integer(id))

    attrs = %{
      name: params["name"],
      description: params["description"],
      content: params["content"] || "",
      content_type: params["content_type"] || "text",
      tags: parse_tags(params["tags"] || "")
    }

    case Library.update_dictionary(dict, attrs) do
      {:ok, _} ->
        {:noreply, socket |> assign(editing_dictionary: nil) |> put_flash(:info, "Dictionary saved.") |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update dictionary.")}
    end
  end

  @impl true
  def handle_event("upload_dictionary", %{"dictionary" => params}, socket) do
    entries =
      consume_uploaded_entries(socket, :dictionary_file, fn %{path: path}, entry ->
        {:ok, {File.read!(path), entry.client_name}}
      end)

    case entries do
      [{content, filename}] ->
        content_type = detect_content_type(filename)

        attrs = %{
          name: if(params["name"] && params["name"] != "", do: params["name"], else: Path.rootname(filename)),
          description: params["description"],
          content: content,
          content_type: content_type,
          filename: filename,
          tags: parse_tags(params["tags"] || "")
        }

        case Library.create_dictionary(attrs) do
          {:ok, _} -> {:noreply, socket |> put_flash(:info, "#{filename} uploaded.") |> load_data()}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Upload failed.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Please select a file to upload.")}
    end
  end

  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("expand_book", %{"book-id" => id}, socket) do
    expanding = if socket.assigns.expanding == id, do: nil, else: id
    {:noreply, assign(socket, expanding: expanding)}
  end

  @impl true
  def handle_event("add_scroll", %{"book-id" => book_id}, socket) do
    book = Book.get(book_id)

    if book do
      %Source{}
      |> Source.changeset(%{
        source_type: book.source_type,
        config: book.default_config,
        book_id: book.id,
        status: "paused"
      })
      |> ExCalibur.Repo.insert()

      broadcast_sources()
    end

    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("save_book", %{"book-id" => book_id} = params, socket) do
    book = Book.get(book_id)

    if book do
      config = build_config(book, params)

      %Source{}
      |> Source.changeset(%{
        source_type: book.source_type,
        config: config,
        book_id: book.id,
        status: "paused"
      })
      |> ExCalibur.Repo.insert()

      broadcast_sources()
    end

    {:noreply, socket |> assign(expanding: nil) |> load_data()}
  end

  @impl true
  def handle_event("save_source_config", %{"source-id" => id} = params, socket) do
    source = ExCalibur.Repo.get!(Source, id)
    book = Book.get(source.book_id)
    config = if book, do: build_config(book, params), else: source.config

    source
    |> Source.changeset(%{config: config})
    |> ExCalibur.Repo.update()

    broadcast_sources()
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("resume", %{"id" => id}, socket) do
    source = ExCalibur.Repo.get!(Source, id)

    source
    |> Source.changeset(%{status: "active", error_message: nil})
    |> ExCalibur.Repo.update!()

    SourceSupervisor.start_source(source)
    broadcast_sources()
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("pause", %{"id" => id}, socket) do
    source = ExCalibur.Repo.get!(Source, id)
    source |> Source.changeset(%{status: "paused"}) |> ExCalibur.Repo.update!()
    SourceSupervisor.stop_source(id)
    broadcast_sources()
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    source = ExCalibur.Repo.get!(Source, id)
    SourceSupervisor.stop_source(id)
    ExCalibur.Repo.delete!(source)
    broadcast_sources()
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("toggle_source", %{"id" => id}, socket) do
    expanding = if socket.assigns.expanding == id, do: nil, else: id
    {:noreply, assign(socket, expanding: expanding)}
  end

  @impl true
  def handle_event("preview_herald_type", %{"herald" => %{"type" => type}}, socket) do
    {:noreply, assign(socket, herald_type_preview: type)}
  end

  def handle_event("preview_herald_type", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("create_herald", %{"herald" => params}, socket) do
    config = build_herald_config(params)

    attrs = %{
      name: params["name"],
      type: params["type"],
      config: config
    }

    ExCalibur.Heralds.create_herald(attrs)
    {:noreply, socket |> assign(herald_type_preview: "slack") |> load_data()}
  end

  @impl true
  def handle_event("configure_herald", %{"id" => id}, socket) do
    editing = if socket.assigns.editing_herald == id, do: nil, else: id
    {:noreply, assign(socket, editing_herald: editing)}
  end

  @impl true
  def handle_event("save_herald_config", %{"herald" => params, "_herald_id" => id}, socket) do
    herald = ExCalibur.Repo.get!(Herald, id)
    config = build_herald_config(Map.put(params, "type", herald.type))

    herald
    |> Herald.changeset(%{config: config})
    |> ExCalibur.Repo.update()

    {:noreply, socket |> assign(editing_herald: nil) |> load_data()}
  end

  @impl true
  def handle_event("delete_herald", %{"id" => id}, socket) do
    herald = ExCalibur.Repo.get!(Herald, id)
    ExCalibur.Heralds.delete_herald(herald)
    {:noreply, load_data(socket)}
  end

  defp build_herald_config(%{"type" => "slack"} = p), do: %{"webhook_url" => p["webhook_url"]}

  defp build_herald_config(%{"type" => "webhook"} = p), do: %{"url" => p["url"], "headers" => %{}}

  defp build_herald_config(%{"type" => type} = p) when type in ["github_issue", "github_pr"],
    do: %{
      "token" => p["token"],
      "owner" => p["owner"],
      "repo" => p["repo"],
      "base_branch" => p["base_branch"],
      "file_path" => p["file_path"]
    }

  defp build_herald_config(%{"type" => "email"} = p),
    do: %{"api_key" => p["api_key"], "from" => p["from"], "to" => p["to"]}

  defp build_herald_config(%{"type" => "pagerduty"} = p),
    do: %{"routing_key" => p["routing_key"], "severity" => p["severity"] || "error"}

  defp build_herald_config(_), do: %{}

  defp build_config(book, params) do
    Enum.reduce(book.default_config, %{}, fn {k, default}, acc ->
      Map.put(acc, k, params[k] || to_string(default))
    end)
  end

  defp detect_content_type(filename) do
    case Path.extname(filename) do
      ".md" -> "markdown"
      ".csv" -> "csv"
      ".json" -> "json"
      _ -> "text"
    end
  end

  defp parse_tags(str) do
    str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-10">
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Library</h1>
        <p class="text-muted-foreground mt-1.5">
          Manage active sources and browse scrolls and books to add more.
        </p>
      </div>

      <%!-- Active Sources --%>
      <div>
        <div class="flex items-center gap-2 mb-4">
          <h2 class="text-xl font-semibold">Active Sources</h2>
          <%= if @sources != [] do %>
            <.badge variant="secondary">{length(@sources)}</.badge>
          <% end %>
          <%= if Enum.any?(@sources, &(&1.status == "active")) do %>
            <.button
              type="button"
              variant="outline"
              size="sm"
              phx-click="sync_all"
              disabled={@syncing}
              class="ml-auto"
            >
              {if @syncing, do: "Syncing…", else: "Sync All"}
            </.button>
          <% end %>
        </div>

        <%= if @sources == [] do %>
          <div class="rounded-lg border border-dashed p-6 text-center">
            <p class="text-muted-foreground text-sm">
              No active sources. Browse below to add some.
            </p>
          </div>
        <% else %>
          <div class="space-y-2">
            <%= for source <- @sources do %>
              <.source_row source={source} expanding={@expanding} />
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Browse --%>
      <div>
        <h2 class="text-xl font-semibold mb-4">Browse</h2>

        <%!-- Tabs --%>
        <div class="flex gap-1 border-b">
          <button
            type="button"
            phx-click="switch_tab"
            phx-value-tab="scrolls"
            class={[
              "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors",
              if(@tab == :scrolls,
                do: "border-primary text-foreground",
                else: "border-transparent text-muted-foreground hover:text-foreground"
              )
            ]}
          >
            Scrolls
          </button>
          <button
            type="button"
            phx-click="switch_tab"
            phx-value-tab="books"
            class={[
              "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors",
              if(@tab == :books,
                do: "border-primary text-foreground",
                else: "border-transparent text-muted-foreground hover:text-foreground"
              )
            ]}
          >
            Books
          </button>
          <button
            type="button"
            phx-click="switch_tab"
            phx-value-tab="heralds"
            class={[
              "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors",
              if(@tab == :heralds,
                do: "border-primary text-foreground",
                else: "border-transparent text-muted-foreground hover:text-foreground"
              )
            ]}
          >
            Heralds
          </button>
          <button
            type="button"
            phx-click="switch_tab"
            phx-value-tab="dictionaries"
            class={[
              "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors",
              if(@tab == :dictionaries,
                do: "border-primary text-foreground",
                else: "border-transparent text-muted-foreground hover:text-foreground"
              )
            ]}
          >
            Dictionaries
          </button>
        </div>
        <p class="text-sm text-muted-foreground mt-3 mb-6">
          <%= if @tab == :scrolls do %>
            Pre-configured feeds — just click Add and they start pulling in content. No setup required.
          <% end %>
          <%= if @tab == :books do %>
            Configurable sources — you provide the path, URL, or endpoint. Requires setup before use.
          <% end %>
          <%= if @tab == :heralds do %>
            Named delivery integrations. Quests use heralds to send results to Slack, GitHub, webhooks, email, or PagerDuty.
          <% end %>
          <%= if @tab == :dictionaries do %>
            Static reference datasets — glossaries, taxonomies, knowledge base docs — wired to steps as context.
          <% end %>
        </p>

        <%= if @tab == :scrolls do %>
          <%= if @scroll_groups == [] do %>
            <p class="text-muted-foreground text-sm">All scrolls added ✓</p>
          <% else %>
            <div class="space-y-8">
              <%= for {guild, items} <- @scroll_groups do %>
                <.guild_section>
                  <:header>{guild}</:header>
                  <%= for item <- items do %>
                    <.scroll_row item={item} />
                  <% end %>
                </.guild_section>
              <% end %>
            </div>
          <% end %>
        <% end %>

        <%= if @tab == :books do %>
          <%= if @book_groups == [] do %>
            <p class="text-muted-foreground text-sm">All books added ✓</p>
          <% else %>
            <div class="space-y-8">
              <%= for {guild, items} <- @book_groups do %>
                <.guild_section>
                  <:header>{guild}</:header>
                  <%= for item <- items do %>
                    <.book_row item={item} expanding={@expanding} />
                  <% end %>
                </.guild_section>
              <% end %>
            </div>
          <% end %>
        <% end %>

        <%= if @tab == :dictionaries do %>
          <div class="space-y-6">
            <%!-- Existing dictionaries --%>
            <%= if @dictionaries == [] do %>
              <p class="text-sm text-muted-foreground">No dictionaries yet. Add one below.</p>
            <% else %>
              <div class="space-y-2">
                <%= for dict <- @dictionaries do %>
                  <div class="rounded-lg border overflow-hidden">
                    <div
                      class="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between cursor-pointer hover:bg-muted/20 transition-colors"
                      phx-click="edit_dictionary"
                      phx-value-id={dict.id}
                    >
                      <div class="flex items-center gap-3 min-w-0 flex-1">
                        <span class={[
                          "transition-transform inline-block text-muted-foreground shrink-0 text-lg leading-none",
                          if(@editing_dictionary == to_string(dict.id), do: "rotate-90")
                        ]}>
                          ›
                        </span>
                        <div class="space-y-1 min-w-0">
                          <div class="flex items-center gap-2 flex-wrap">
                            <span class="font-medium">{dict.name}</span>
                            <.badge variant="secondary">{dict.content_type}</.badge>
                            <%= if dict.filename do %>
                              <.badge variant="outline" class="text-xs">{dict.filename}</.badge>
                            <% end %>
                          </div>
                          <%= if dict.description do %>
                            <p class="text-sm text-muted-foreground">{dict.description}</p>
                          <% end %>
                          <%= if dict.tags != [] do %>
                            <p class="text-xs text-muted-foreground">
                              Tags: {Enum.join(dict.tags, ", ")}
                            </p>
                          <% end %>
                          <%= if dict.content && dict.content != "" do %>
                            <p class="text-xs text-muted-foreground font-mono truncate max-w-md">
                              {String.slice(dict.content, 0, 120)}{if String.length(dict.content) >
                                                                        120,
                                                                      do: "…"}
                            </p>
                          <% end %>
                        </div>
                      </div>
                      <div class="shrink-0 self-start sm:self-auto">
                        <.button
                          size="sm"
                          variant="destructive"
                          phx-click="delete_dictionary"
                          phx-value-id={dict.id}
                          data-confirm={"Delete dictionary \"#{dict.name}\"?"}
                        >
                          Delete
                        </.button>
                      </div>
                    </div>
                    <%= if @editing_dictionary == to_string(dict.id) do %>
                      <div class="border-t bg-muted/30 px-4 py-4">
                        <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
                          Edit
                        </p>
                        <form
                          id={"dict-edit-#{dict.id}"}
                          phx-submit="update_dictionary"
                          class="space-y-3"
                        >
                          <input type="hidden" name="_dictionary_id" value={dict.id} />
                          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                            <div>
                              <label class="text-sm font-medium">Name</label>
                              <input
                                type="text"
                                name="dictionary[name]"
                                value={dict.name}
                                class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                              />
                            </div>
                            <div>
                              <label class="text-sm font-medium">Type</label>
                              <select
                                name="dictionary[content_type]"
                                class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                              >
                                <%= for ct <- ~w(text markdown csv json) do %>
                                  <option value={ct} selected={dict.content_type == ct}>{ct}</option>
                                <% end %>
                              </select>
                            </div>
                          </div>
                          <div>
                            <label class="text-sm font-medium">Description</label>
                            <input
                              type="text"
                              name="dictionary[description]"
                              value={dict.description || ""}
                              placeholder="Optional"
                              class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                            />
                          </div>
                          <div>
                            <label class="text-sm font-medium">Tags</label>
                            <input
                              type="text"
                              name="dictionary[tags]"
                              value={Enum.join(dict.tags, ", ")}
                              placeholder="comma-separated"
                              class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                            />
                          </div>
                          <div>
                            <label class="text-sm font-medium">Content</label>
                            <textarea
                              name="dictionary[content]"
                              rows="8"
                              class="w-full text-sm border border-input rounded-md px-3 py-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring font-mono"
                            >{dict.content}</textarea>
                          </div>
                          <div class="flex justify-end gap-2">
                            <.button type="submit" size="sm">Save</.button>
                          </div>
                        </form>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>

            <%!-- Add dictionary form --%>
            <div class="border rounded-lg border-dashed p-4">
              <p class="text-sm font-medium mb-3">Add Dictionary</p>
              <form phx-submit="create_dictionary" class="space-y-3">
                <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <div>
                    <label class="text-sm font-medium">Name</label>
                    <input
                      type="text"
                      name="dictionary[name]"
                      placeholder="e.g. Product Glossary"
                      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                    />
                  </div>
                  <div>
                    <label class="text-sm font-medium">Type</label>
                    <select
                      name="dictionary[content_type]"
                      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                    >
                      <option value="text">Text</option>
                      <option value="markdown">Markdown</option>
                      <option value="csv">CSV</option>
                      <option value="json">JSON</option>
                    </select>
                  </div>
                </div>
                <div>
                  <label class="text-sm font-medium">Description</label>
                  <input
                    type="text"
                    name="dictionary[description]"
                    placeholder="Optional"
                    class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                  />
                </div>
                <div>
                  <label class="text-sm font-medium">Tags</label>
                  <input
                    type="text"
                    name="dictionary[tags]"
                    placeholder="comma-separated"
                    class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                  />
                </div>
                <div>
                  <label class="text-sm font-medium">Content</label>
                  <textarea
                    name="dictionary[content]"
                    rows="6"
                    placeholder="Paste your reference content here…"
                    class="w-full text-sm border border-input rounded-md px-3 py-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring font-mono"
                  ></textarea>
                </div>
                <div class="flex justify-end">
                  <.button type="submit" size="sm">Add Dictionary</.button>
                </div>
              </form>
            </div>

            <%!-- File upload --%>
            <div class="border rounded-lg border-dashed p-4">
              <p class="text-sm font-medium mb-3">Upload File</p>
              <form
                phx-submit="upload_dictionary"
                phx-change="validate_upload"
                class="space-y-3"
              >
                <.live_file_input upload={@uploads.dictionary_file} class="text-sm" />
                <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <div>
                    <label class="text-sm font-medium">Name (optional)</label>
                    <input
                      type="text"
                      name="dictionary[name]"
                      placeholder="Defaults to filename"
                      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                    />
                  </div>
                  <div>
                    <label class="text-sm font-medium">Tags (optional)</label>
                    <input
                      type="text"
                      name="dictionary[tags]"
                      placeholder="tags, comma-separated"
                      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                    />
                  </div>
                </div>
                <div class="flex justify-end">
                  <.button type="submit" size="sm">Upload</.button>
                </div>
              </form>
            </div>
          </div>
        <% end %>

        <%= if @tab == :heralds do %>
          <div class="space-y-6">
            <%!-- Existing heralds --%>
            <div class="space-y-2">
              <%= for herald <- @heralds do %>
                <div class="rounded-lg border overflow-hidden">
                  <div
                    class="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between cursor-pointer hover:bg-muted/20 transition-colors"
                    phx-click="configure_herald"
                    phx-value-id={herald.id}
                  >
                    <div class="flex items-center gap-3 min-w-0 flex-1">
                      <span class={[
                        "transition-transform inline-block text-muted-foreground shrink-0 text-lg leading-none",
                        if(@editing_herald == to_string(herald.id), do: "rotate-90")
                      ]}>
                        ›
                      </span>
                      <div class="space-y-1 min-w-0">
                        <div class="flex items-center gap-2 flex-wrap">
                          <span class="font-medium">{herald.name}</span>
                          <.badge variant="secondary">{herald.type}</.badge>
                          <%= if herald.config == %{} or Enum.all?(herald.config, fn {_, v} -> v == "" end) do %>
                            <.badge variant="destructive" class="text-xs">needs config</.badge>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  </div>
                  <%= if @editing_herald == to_string(herald.id) do %>
                    <div class="border-t bg-muted/30 px-4 py-4">
                      <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
                        Configure
                      </p>
                      <.herald_config_form herald={herald} />
                      <div class="flex items-center gap-2 pt-3">
                        <.button type="submit" form={"herald-config-#{herald.id}"} size="sm">
                          Save
                        </.button>
                        <%= unless String.ends_with?(herald.name, ":default") do %>
                          <.button
                            size="sm"
                            variant="destructive"
                            phx-click="delete_herald"
                            phx-value-id={herald.id}
                            data-confirm="Delete this herald?"
                          >
                            Delete
                          </.button>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
              <%= if @heralds == [] do %>
                <p class="text-sm text-muted-foreground">No heralds configured yet.</p>
              <% end %>
            </div>

            <%!-- Add herald form --%>
            <div class="border rounded-lg border-dashed p-4">
              <p class="text-sm font-medium mb-3">Add Herald</p>
              <form phx-submit="create_herald" phx-change="preview_herald_type" class="space-y-3">
                <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <div>
                    <label class="text-sm font-medium">Name</label>
                    <input
                      type="text"
                      name="herald[name]"
                      placeholder="e.g. slack:engineering"
                      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                    />
                  </div>
                  <div>
                    <label class="text-sm font-medium">Type</label>
                    <select
                      name="herald[type]"
                      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                    >
                      <option value="slack" selected={@herald_type_preview == "slack"}>Slack</option>
                      <option value="webhook" selected={@herald_type_preview == "webhook"}>
                        Webhook
                      </option>
                      <option value="github_issue" selected={@herald_type_preview == "github_issue"}>
                        GitHub Issue
                      </option>
                      <option value="github_pr" selected={@herald_type_preview == "github_pr"}>
                        GitHub PR
                      </option>
                      <option value="email" selected={@herald_type_preview == "email"}>
                        Email (Resend)
                      </option>
                      <option value="pagerduty" selected={@herald_type_preview == "pagerduty"}>
                        PagerDuty
                      </option>
                    </select>
                  </div>
                </div>

                <%= if @herald_type_preview == "slack" do %>
                  <div>
                    <label class="text-sm font-medium">Incoming Webhook URL</label>
                    <input
                      type="text"
                      name="herald[webhook_url]"
                      placeholder="https://hooks.slack.com/services/..."
                      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                    />
                  </div>
                <% end %>

                <%= if @herald_type_preview == "webhook" do %>
                  <div>
                    <label class="text-sm font-medium">URL</label>
                    <input
                      type="text"
                      name="herald[url]"
                      placeholder="https://your-endpoint.com/hook"
                      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                    />
                  </div>
                <% end %>

                <%= if @herald_type_preview in ["github_issue", "github_pr"] do %>
                  <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
                    <div>
                      <label class="text-sm font-medium">Token</label>
                      <input
                        type="password"
                        name="herald[token]"
                        placeholder="ghp_..."
                        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                      />
                    </div>
                    <div>
                      <label class="text-sm font-medium">Owner</label>
                      <input
                        type="text"
                        name="herald[owner]"
                        placeholder="acme-corp"
                        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                      />
                    </div>
                    <div>
                      <label class="text-sm font-medium">Repo</label>
                      <input
                        type="text"
                        name="herald[repo]"
                        placeholder="my-repo"
                        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                      />
                    </div>
                  </div>
                  <%= if @herald_type_preview == "github_pr" do %>
                    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                      <div>
                        <label class="text-sm font-medium">Base branch</label>
                        <input
                          type="text"
                          name="herald[base_branch]"
                          value="main"
                          class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                        />
                      </div>
                      <div>
                        <label class="text-sm font-medium">File path template</label>
                        <input
                          type="text"
                          name="herald[file_path]"
                          placeholder="docs/reports/report.md"
                          class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                        />
                      </div>
                    </div>
                  <% end %>
                <% end %>

                <%= if @herald_type_preview == "email" do %>
                  <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
                    <div>
                      <label class="text-sm font-medium">Resend API key</label>
                      <input
                        type="password"
                        name="herald[api_key]"
                        placeholder="re_..."
                        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                      />
                    </div>
                    <div>
                      <label class="text-sm font-medium">From</label>
                      <input
                        type="text"
                        name="herald[from]"
                        placeholder="reports@yourdomain.com"
                        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                      />
                    </div>
                    <div>
                      <label class="text-sm font-medium">To</label>
                      <input
                        type="text"
                        name="herald[to]"
                        placeholder="team@yourdomain.com"
                        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                      />
                    </div>
                  </div>
                <% end %>

                <%= if @herald_type_preview == "pagerduty" do %>
                  <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <div>
                      <label class="text-sm font-medium">Routing key</label>
                      <input
                        type="password"
                        name="herald[routing_key]"
                        placeholder="..."
                        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                      />
                    </div>
                    <div>
                      <label class="text-sm font-medium">Severity</label>
                      <select
                        name="herald[severity]"
                        class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
                      >
                        <option value="critical">Critical</option>
                        <option value="error" selected>Error</option>
                        <option value="warning">Warning</option>
                        <option value="info">Info</option>
                      </select>
                    </div>
                  </div>
                <% end %>

                <div class="flex justify-end">
                  <.button type="submit" size="sm">Add Herald</.button>
                </div>
              </form>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ── Components ────────────────────────────────────────────────────────────

  slot :header, required: true
  slot :inner_block, required: true

  defp guild_section(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-3 mb-3">
        <h3 class="text-sm font-semibold uppercase tracking-wider text-muted-foreground whitespace-nowrap">
          {render_slot(@header)}
        </h3>
        <div class="flex-1 h-px bg-border"></div>
      </div>
      <div class="space-y-2">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :item, :map, required: true

  defp scroll_row(assigns) do
    ~H"""
    <div class="flex flex-col gap-3 rounded-lg border p-4 sm:flex-row sm:items-center sm:justify-between">
      <div class="space-y-1 min-w-0">
        <div class="flex items-center gap-2 flex-wrap">
          <span class="font-medium">{@item.name}</span>
          <.badge variant="secondary">{@item.source_type}</.badge>
        </div>
        <p class="text-sm text-muted-foreground">{@item.description}</p>
      </div>
      <div class="shrink-0 self-start sm:self-auto">
        <.button
          type="button"
          variant="outline"
          size="sm"
          phx-click="add_scroll"
          phx-value-book-id={@item.id}
        >
          Add
        </.button>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :expanding, :string, default: nil

  defp book_row(assigns) do
    ~H"""
    <div class="rounded-lg border overflow-hidden">
      <div class="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
        <div class="space-y-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <span class="font-medium">{@item.name}</span>
            <.badge variant="secondary">{@item.source_type}</.badge>
          </div>
          <p class="text-sm text-muted-foreground">{@item.description}</p>
        </div>
        <div class="shrink-0 self-start sm:self-auto">
          <.button
            variant="outline"
            size="sm"
            phx-click="expand_book"
            phx-value-book-id={@item.id}
          >
            {if @expanding == @item.id, do: "Cancel", else: "Add"}
          </.button>
        </div>
      </div>

      <%= if @expanding == @item.id do %>
        <div class="border-t bg-muted/30 px-4 py-4">
          <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
            Configure
          </p>
          <form phx-submit="save_book" class="space-y-3">
            <input type="hidden" name="book-id" value={@item.id} />
            <.config_fields config={@item.default_config} source_type={@item.source_type} />
            <div class="flex justify-end pt-1">
              <.button type="submit" size="sm">Save & Add</.button>
            </div>
          </form>
        </div>
      <% end %>
    </div>
    """
  end

  attr :source, :map, required: true
  attr :expanding, :string, default: nil

  defp source_row(assigns) do
    assigns = assign(assigns, :name, source_name(assigns.source))

    ~H"""
    <div class="rounded-lg border overflow-hidden">
      <div
        class="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between cursor-pointer hover:bg-muted/20 transition-colors"
        phx-click="toggle_source"
        phx-value-id={@source.id}
      >
        <div class="flex items-center gap-3 min-w-0 flex-1">
          <span class={[
            "transition-transform inline-block text-muted-foreground shrink-0 text-lg leading-none",
            if(@expanding == @source.id, do: "rotate-90")
          ]}>
            ›
          </span>
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2 flex-wrap">
              <span class="font-medium">{@name}</span>
              <.badge variant="outline">{@source.source_type}</.badge>
              <.status_badge status={@source.status} />
            </div>
            <%= if @source.error_message do %>
              <p class="text-xs text-destructive mt-0.5">{@source.error_message}</p>
            <% end %>
            <p class="text-xs text-muted-foreground mt-0.5">
              Last run: {format_time(@source.last_run_at)}
            </p>
            <%= if @source.source_type == "webhook" do %>
              <p class="text-xs text-muted-foreground font-mono mt-0.5">
                POST /api/webhooks/{@source.id}
              </p>
            <% end %>
          </div>
        </div>
        <div class="flex gap-2 shrink-0 self-start sm:self-auto" phx-click="" phx-click-stop="">
          <%= if @source.status == "active" do %>
            <.button
              type="button"
              variant="outline"
              size="sm"
              phx-click="sync"
              phx-value-id={@source.id}
            >
              Sync
            </.button>
            <.button
              type="button"
              variant="outline"
              size="sm"
              phx-click="pause"
              phx-value-id={@source.id}
            >
              Pause
            </.button>
          <% else %>
            <.button
              type="button"
              variant="outline"
              size="sm"
              phx-click="resume"
              phx-value-id={@source.id}
            >
              Resume
            </.button>
          <% end %>
          <.button
            variant="destructive"
            size="sm"
            phx-click="delete"
            phx-value-id={@source.id}
            data-confirm="Remove this source?"
          >
            Delete
          </.button>
        </div>
      </div>

      <%= if @expanding == @source.id do %>
        <div class="border-t bg-muted/30 px-4 py-4">
          <%= if @source.source_type == "webhook" do %>
            <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
              Endpoint
            </p>
            <p class="text-sm font-mono text-muted-foreground">
              POST /api/webhooks/{@source.id}
            </p>
            <p class="text-xs text-muted-foreground mt-1">
              Send a Bearer token in the Authorization header to authenticate requests.
            </p>
          <% else %>
            <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
              Configuration
            </p>
            <form phx-submit="save_source_config" class="space-y-3">
              <input type="hidden" name="source-id" value={@source.id} />
              <.config_fields config={@source.config} source_type={@source.source_type} />
              <div class="flex justify-end pt-1">
                <.button type="submit" size="sm" variant="outline">Save</.button>
              </div>
            </form>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :status, :string, required: true

  defp status_badge(assigns) do
    {variant, label} =
      case assigns.status do
        "active" -> {"default", "active"}
        "paused" -> {"secondary", "paused"}
        "error" -> {"destructive", "error"}
        s -> {"outline", s}
      end

    assigns = assign(assigns, variant: variant, label: label)

    ~H"""
    <.badge variant={@variant}>{@label}</.badge>
    """
  end

  attr :config, :map, required: true
  attr :source_type, :string, required: true

  defp config_fields(assigns) do
    ~H"""
    <div class="space-y-3">
      <%= for {key, value} <- Enum.sort(@config) do %>
        <div class="space-y-1">
          <label class="text-sm font-medium">{humanize_key(key)}</label>
          <%= if key == "interval" do %>
            <.input
              type="text"
              name={key}
              value={format_interval(value)}
              placeholder="e.g. 60s, 5m, 1h"
            />
            <p class="text-xs text-muted-foreground">How often to poll (e.g. 30s, 5m, 1h)</p>
          <% else %>
            <.input
              type="text"
              name={key}
              value={if is_binary(value), do: value, else: ""}
              placeholder={placeholder_for(key)}
            />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp humanize_key(key) do
    key
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_interval(ms) when is_integer(ms) do
    cond do
      rem(ms, 3_600_000) == 0 -> "#{div(ms, 3_600_000)}h"
      rem(ms, 60_000) == 0 -> "#{div(ms, 60_000)}m"
      rem(ms, 1_000) == 0 -> "#{div(ms, 1_000)}s"
      true -> "#{ms}ms"
    end
  end

  defp format_interval(v), do: to_string(v)

  defp placeholder_for("url"), do: "https://..."
  defp placeholder_for("repo_path"), do: "/path/to/repo"
  defp placeholder_for("path"), do: "/path/to/directory"
  defp placeholder_for("branch"), do: "main"
  defp placeholder_for("message_path"), do: "$.message"
  defp placeholder_for("patterns"), do: "*.ex, *.heex"
  defp placeholder_for(_), do: ""

  attr :herald, :map, required: true

  defp herald_config_form(assigns) do
    ~H"""
    <form id={"herald-config-#{@herald.id}"} phx-submit="save_herald_config" class="space-y-3">
      <input type="hidden" name="_herald_id" value={@herald.id} />
      <%= if @herald.type == "slack" do %>
        <div>
          <label class="text-xs text-muted-foreground">Webhook URL</label>
          <input
            type="text"
            name="herald[webhook_url]"
            value={@herald.config["webhook_url"]}
            placeholder="https://hooks.slack.com/services/..."
            class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
          />
        </div>
      <% end %>
      <%= if @herald.type == "webhook" do %>
        <div>
          <label class="text-xs text-muted-foreground">URL</label>
          <input
            type="text"
            name="herald[url]"
            value={@herald.config["url"]}
            placeholder="https://..."
            class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
          />
        </div>
      <% end %>
      <%= if @herald.type in ["github_issue", "github_pr"] do %>
        <div class="grid grid-cols-2 gap-2">
          <div>
            <label class="text-xs text-muted-foreground">Owner</label>
            <input
              type="text"
              name="herald[owner]"
              value={@herald.config["owner"]}
              placeholder="org-or-user"
              class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
            />
          </div>
          <div>
            <label class="text-xs text-muted-foreground">Repo</label>
            <input
              type="text"
              name="herald[repo]"
              value={@herald.config["repo"]}
              placeholder="repo-name"
              class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
            />
          </div>
        </div>
        <div>
          <label class="text-xs text-muted-foreground">Token</label>
          <input
            type="password"
            name="herald[token]"
            value={@herald.config["token"]}
            placeholder="ghp_..."
            class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
          />
        </div>
        <%= if @herald.type == "github_pr" do %>
          <div class="grid grid-cols-2 gap-2">
            <div>
              <label class="text-xs text-muted-foreground">Base Branch</label>
              <input
                type="text"
                name="herald[base_branch]"
                value={@herald.config["base_branch"] || "main"}
                class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
              />
            </div>
            <div>
              <label class="text-xs text-muted-foreground">File Path</label>
              <input
                type="text"
                name="herald[file_path]"
                value={@herald.config["file_path"]}
                placeholder="docs/report.md"
                class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
              />
            </div>
          </div>
        <% end %>
      <% end %>
      <%= if @herald.type == "email" do %>
        <div class="grid grid-cols-2 gap-2">
          <div>
            <label class="text-xs text-muted-foreground">From</label>
            <input
              type="text"
              name="herald[from]"
              value={@herald.config["from"]}
              placeholder="no-reply@example.com"
              class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
            />
          </div>
          <div>
            <label class="text-xs text-muted-foreground">To</label>
            <input
              type="text"
              name="herald[to]"
              value={@herald.config["to"]}
              placeholder="team@example.com"
              class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
            />
          </div>
        </div>
        <div>
          <label class="text-xs text-muted-foreground">Resend API Key</label>
          <input
            type="password"
            name="herald[api_key]"
            value={@herald.config["api_key"]}
            placeholder="re_..."
            class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
          />
        </div>
      <% end %>
      <%= if @herald.type == "pagerduty" do %>
        <div class="grid grid-cols-2 gap-2">
          <div>
            <label class="text-xs text-muted-foreground">Routing Key</label>
            <input
              type="password"
              name="herald[routing_key]"
              value={@herald.config["routing_key"]}
              placeholder="PD routing key"
              class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
            />
          </div>
          <div>
            <label class="text-xs text-muted-foreground">Severity</label>
            <select
              name="herald[severity]"
              class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
            >
              <%= for sev <- ~w(critical error warning info) do %>
                <option value={sev} selected={@herald.config["severity"] == sev}>{sev}</option>
              <% end %>
            </select>
          </div>
        </div>
      <% end %>
    </form>
    """
  end
end
