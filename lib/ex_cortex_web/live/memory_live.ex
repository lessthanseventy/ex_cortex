defmodule ExCortexWeb.MemoryLive do
  @moduledoc false
  use ExCortexWeb, :live_view

  import SaladUI.Badge

  alias ExCortex.Memory

  @categories [
    {"all", "All"},
    {"episodic", "Episodic"},
    {"semantic", "Semantic"},
    {"procedural", "Procedural"}
  ]

  @category_colors %{
    "episodic" => "cyan",
    "semantic" => "green",
    "procedural" => "amber"
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCortex.PubSub, "memory")
    end

    engrams = Memory.list_engrams([])

    {:ok,
     assign(socket,
       page_title: "Memory",
       category: "all",
       engrams: engrams,
       selected_engram: nil,
       detail_level: :impression,
       search_query: "",
       show_create_form: false,
       create_form: %{
         "title" => "",
         "body" => "",
         "tags" => "",
         "category" => "semantic",
         "importance" => "5",
         "source" => ""
       },
       create_error: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:engram_updated, _entry}, socket) do
    {:noreply, reload_engrams(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select_category", %{"category" => category}, socket) do
    socket =
      socket
      |> assign(category: category, selected_engram: nil, detail_level: :impression)
      |> reload_engrams()

    {:noreply, socket}
  end

  def handle_event("select_engram", %{"id" => id}, socket) do
    id = String.to_integer(id)

    if socket.assigns.selected_engram && socket.assigns.selected_engram.id == id do
      {:noreply, assign(socket, selected_engram: nil, detail_level: :impression)}
    else
      engram = Memory.load_recall(id)
      {:noreply, assign(socket, selected_engram: engram, detail_level: :recall)}
    end
  end

  def handle_event("load_deep", %{"id" => id}, socket) do
    id = String.to_integer(id)
    engram = Memory.load_deep(id)
    {:noreply, assign(socket, selected_engram: engram, detail_level: :deep)}
  end

  def handle_event("search", %{"q" => q}, socket) do
    q = String.trim(q)

    engrams =
      if q == "" do
        Memory.list_engrams(category_opts(socket.assigns.category))
      else
        Memory.query(q, category_opts(socket.assigns.category))
      end

    {:noreply,
     assign(socket,
       search_query: q,
       engrams: engrams,
       selected_engram: nil,
       detail_level: :impression
     )}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(search_query: "", selected_engram: nil, detail_level: :impression)
     |> reload_engrams()}
  end

  def handle_event("show_create_form", _params, socket) do
    {:noreply, assign(socket, show_create_form: true, create_error: nil)}
  end

  def handle_event("hide_create_form", _params, socket) do
    {:noreply, assign(socket, show_create_form: false, create_error: nil)}
  end

  def handle_event("update_create_form", %{"field" => field, "value" => value}, socket) do
    form = Map.put(socket.assigns.create_form, field, value)
    {:noreply, assign(socket, create_form: form)}
  end

  def handle_event("create_engram", params, socket) do
    tags =
      params
      |> Map.get("tags", "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    importance =
      params
      |> Map.get("importance", "5")
      |> Integer.parse()
      |> case do
        {n, _} -> n
        :error -> 5
      end

    attrs = %{
      title: params["title"],
      body: params["body"],
      tags: tags,
      category: params["category"],
      importance: importance,
      source: params["source"]
    }

    case Memory.create_engram(attrs) do
      {:ok, _engram} ->
        {:noreply,
         socket
         |> assign(
           show_create_form: false,
           create_error: nil,
           create_form: %{
             "title" => "",
             "body" => "",
             "tags" => "",
             "category" => "semantic",
             "importance" => "5",
             "source" => ""
           }
         )
         |> reload_engrams()}

      {:error, changeset} ->
        error =
          Enum.map_join(changeset.errors, ", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)

        {:noreply, assign(socket, create_error: error)}
    end
  end

  def handle_event("navigate", %{"to" => path}, socket) do
    {:noreply, push_navigate(socket, to: path)}
  end

  defp reload_engrams(socket) do
    opts = category_opts(socket.assigns.category)

    engrams =
      if socket.assigns.search_query == "" do
        Memory.list_engrams(opts)
      else
        Memory.query(socket.assigns.search_query, opts)
      end

    assign(socket, engrams: engrams)
  end

  defp category_opts("all"), do: []
  defp category_opts(cat), do: [category: cat]

  defp category_color(category), do: Map.get(@category_colors, category, "dim")

  defp importance_label(nil), do: ""
  defp importance_label(n) when n >= 8, do: "high"
  defp importance_label(n) when n >= 5, do: "mid"
  defp importance_label(_), do: "low"

  defp importance_color(nil), do: "dim"
  defp importance_color(n) when n >= 8, do: "pink"
  defp importance_color(n) when n >= 5, do: "amber"
  defp importance_color(_), do: "dim"

  defp format_time(nil), do: "—"

  defp format_time(dt) do
    Calendar.strftime(dt, "%b %d %H:%M")
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :categories, @categories)

    ~H"""
    <div class="space-y-4">
      <%!-- Header --%>
      <.panel title="MEMORY BROWSER">
        <div class="flex items-center justify-between gap-4 flex-wrap">
          <div class="flex items-center gap-4">
            <span class="t-muted text-xs">
              {length(@engrams)} engrams
            </span>
            <.key_hints hints={[{"s", "search"}, {"n", "new"}, {"esc", "close"}]} />
          </div>
          <button
            class="tui-btn text-xs"
            phx-click="show_create_form"
          >
            [n] new engram
          </button>
        </div>
      </.panel>

      <%!-- Category tabs --%>
      <.panel title="CATEGORY">
        <div class="flex gap-3 flex-wrap">
          <%= for {key, label} <- @categories do %>
            <button
              class={"tui-tab #{if @category == key, do: "active"}"}
              phx-click="select_category"
              phx-value-category={key}
            >
              <%= if key == "all" do %>
                <.status color="dim" label={label} />
              <% else %>
                <.status color={category_color(key)} label={label} />
              <% end %>
            </button>
          <% end %>
        </div>
      </.panel>

      <%!-- Search bar --%>
      <.panel title="SEARCH">
        <form phx-submit="search" class="flex gap-2 items-center">
          <span class="t-dim">›</span>
          <input
            type="text"
            name="q"
            value={@search_query}
            placeholder="search engrams..."
            class="tui-input flex-1"
            phx-debounce="300"
          />
          <button type="submit" class="tui-btn text-xs">[s]</button>
          <%= if @search_query != "" do %>
            <button type="button" class="tui-btn text-xs t-dim" phx-click="clear_search">
              [x] clear
            </button>
          <% end %>
        </form>
        <%= if @search_query != "" do %>
          <div class="mt-1 text-xs t-muted">
            {length(@engrams)} result{if length(@engrams) != 1, do: "s"} for "{@search_query}"
          </div>
        <% end %>
      </.panel>

      <%!-- Main two-column layout --%>
      <div class="grid gap-4 md:grid-cols-2">
        <%!-- Engram list --%>
        <.panel title="ENGRAMS">
          <%= if @engrams == [] do %>
            <div class="text-xs t-muted py-4 text-center">
              <%= if @search_query != "" do %>
                No engrams matched "{@search_query}"
              <% else %>
                No engrams in this category yet.
              <% end %>
            </div>
          <% else %>
            <div class="space-y-1">
              <%= for engram <- @engrams do %>
                <button
                  class={"w-full text-left tui-list-item #{if @selected_engram && @selected_engram.id == engram.id, do: "active"}"}
                  phx-click="select_engram"
                  phx-value-id={engram.id}
                >
                  <div class="flex items-start justify-between gap-2">
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-2">
                        <%= if engram.category do %>
                          <.status
                            color={category_color(engram.category)}
                            label={engram.category}
                          />
                        <% end %>
                        <span class="font-mono text-xs truncate">{engram.title}</span>
                      </div>
                      <%= if engram.impression do %>
                        <div class="text-xs t-muted mt-0.5 line-clamp-1">
                          {engram.impression}
                        </div>
                      <% end %>
                    </div>
                    <div class="flex items-center gap-1.5 shrink-0">
                      <%= if engram.importance do %>
                        <.status
                          color={importance_color(engram.importance)}
                          label={importance_label(engram.importance)}
                        />
                      <% end %>
                      <span class="text-xs t-dim">{format_time(engram.inserted_at)}</span>
                    </div>
                  </div>
                </button>
              <% end %>
            </div>
          <% end %>
        </.panel>

        <%!-- Detail panel --%>
        <.panel title={if @selected_engram, do: "ENGRAM DETAIL", else: "SELECT AN ENGRAM"}>
          <%= if @selected_engram do %>
            <.engram_detail engram={@selected_engram} detail_level={@detail_level} />
          <% else %>
            <div class="text-xs t-muted py-8 text-center">
              Click an engram to view its recall (L1). <br />
              Click again or press "deep" to load full body (L2).
            </div>
          <% end %>
        </.panel>
      </div>

      <%!-- Create engram form --%>
      <%= if @show_create_form do %>
        <.panel title="NEW ENGRAM">
          <.create_engram_form form={@create_form} error={@create_error} />
        </.panel>
      <% end %>
    </div>
    """
  end

  attr :engram, :map, required: true
  attr :detail_level, :atom, required: true

  defp engram_detail(assigns) do
    ~H"""
    <div class="space-y-3 text-sm">
      <div class="flex items-center justify-between gap-2 flex-wrap">
        <span class="font-mono t-bright">{@engram.title}</span>
        <div class="flex items-center gap-2">
          <%= if @engram.category do %>
            <.status color={category_color(@engram.category)} label={@engram.category} />
          <% end %>
          <%= if @engram.importance do %>
            <.status
              color={importance_color(@engram.importance)}
              label={"importance #{@engram.importance}"}
            />
          <% end %>
        </div>
      </div>

      <%= if @engram.tags && @engram.tags != [] do %>
        <div class="flex flex-wrap gap-1">
          <%= for tag <- @engram.tags do %>
            <.badge variant="secondary" class="text-xs font-mono">{tag}</.badge>
          <% end %>
        </div>
      <% end %>

      <div class="grid grid-cols-2 gap-x-4 gap-y-1 text-xs t-muted">
        <%= if @engram.source do %>
          <div><span class="t-dim">source:</span> {@engram.source}</div>
        <% end %>
        <%= if @engram.cluster_name do %>
          <div><span class="t-dim">cluster:</span> {@engram.cluster_name}</div>
        <% end %>
        <div><span class="t-dim">created:</span> {format_time(@engram.inserted_at)}</div>
      </div>

      <%!-- L0: impression (always shown) --%>
      <%= if @engram.impression do %>
        <div>
          <div class="text-xs t-dim mb-1">L0 impression</div>
          <div class="text-xs t-muted border-l-2 border-muted pl-3">
            {@engram.impression}
          </div>
        </div>
      <% end %>

      <%!-- L1: recall (shown when detail_level is :recall or :deep) --%>
      <%= if @detail_level in [:recall, :deep] and @engram.recall do %>
        <div>
          <div class="text-xs t-dim mb-1">L1 recall</div>
          <div class="text-xs border-l-2 border-cyan-700/50 pl-3 whitespace-pre-wrap">
            {@engram.recall}
          </div>
        </div>
      <% end %>

      <%!-- L2: full body (shown when detail_level is :deep) --%>
      <%= if @detail_level == :deep and @engram.body do %>
        <div>
          <div class="text-xs t-dim mb-1">L2 body</div>
          <div class="text-xs border-l-2 border-green-700/50 pl-3 whitespace-pre-wrap">
            {@engram.body}
          </div>
        </div>
      <% end %>

      <%!-- Drill-down controls --%>
      <div class="flex gap-2 pt-1">
        <%= if @detail_level == :recall do %>
          <button
            class="tui-btn text-xs"
            phx-click="load_deep"
            phx-value-id={@engram.id}
          >
            [d] deep load L2
          </button>
        <% end %>
        <button
          class="tui-btn text-xs t-dim"
          phx-click="select_engram"
          phx-value-id={@engram.id}
        >
          [esc] close
        </button>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :error, :string, default: nil

  defp create_engram_form(assigns) do
    ~H"""
    <form phx-submit="create_engram" class="space-y-3 text-sm">
      <%= if @error do %>
        <div class="text-xs t-red border border-red-700/50 px-3 py-2 rounded">
          {@error}
        </div>
      <% end %>

      <div class="grid gap-3 md:grid-cols-2">
        <div class="space-y-1">
          <label class="text-xs t-dim">title *</label>
          <input
            type="text"
            name="title"
            value={@form["title"]}
            required
            placeholder="engram title"
            class="tui-input w-full"
          />
        </div>

        <div class="space-y-1">
          <label class="text-xs t-dim">category</label>
          <select name="category" class="tui-input w-full">
            <option value="semantic" selected={@form["category"] == "semantic"}>semantic</option>
            <option value="episodic" selected={@form["category"] == "episodic"}>episodic</option>
            <option value="procedural" selected={@form["category"] == "procedural"}>
              procedural
            </option>
          </select>
        </div>
      </div>

      <div class="space-y-1">
        <label class="text-xs t-dim">body</label>
        <textarea
          name="body"
          rows="4"
          placeholder="full engram body (L2)"
          class="tui-input w-full resize-y"
        >{@form["body"]}</textarea>
      </div>

      <div class="grid gap-3 md:grid-cols-2">
        <div class="space-y-1">
          <label class="text-xs t-dim">tags (comma separated)</label>
          <input
            type="text"
            name="tags"
            value={@form["tags"]}
            placeholder="tag1, tag2"
            class="tui-input w-full"
          />
        </div>

        <div class="space-y-1">
          <label class="text-xs t-dim">importance (1–10)</label>
          <input
            type="number"
            name="importance"
            value={@form["importance"]}
            min="1"
            max="10"
            class="tui-input w-full"
          />
        </div>
      </div>

      <div class="space-y-1">
        <label class="text-xs t-dim">source</label>
        <input
          type="text"
          name="source"
          value={@form["source"]}
          placeholder="origin or context"
          class="tui-input w-full"
        />
      </div>

      <div class="flex gap-2 pt-1">
        <button type="submit" class="tui-btn text-xs">
          [enter] create engram
        </button>
        <button type="button" class="tui-btn text-xs t-dim" phx-click="hide_create_form">
          [esc] cancel
        </button>
      </div>
    </form>
    """
  end
end
