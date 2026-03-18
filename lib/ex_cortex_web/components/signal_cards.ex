defmodule ExCortexWeb.Components.SignalCards do
  @moduledoc "Function components for rendering signal cards by type."
  use Phoenix.Component

  import SaladUI.Badge
  import SaladUI.Button
  import SaladUI.Card

  @preset_tags ~w(tech urgent meeting todo idea)
  def preset_tags, do: @preset_tags

  attr :card, :map, required: true

  def signal_card(%{card: %{type: "note"}} = assigns) do
    ~H"""
    <.signal_card_frame card={@card}>
      <.md_body body={@card.body} />
    </.signal_card_frame>
    """
  end

  def signal_card(%{card: %{type: "checklist"}} = assigns) do
    items = assigns.card.metadata["items"] || []
    brain_dump = assigns.card.metadata["brain_dump"] || []
    has_handler = assigns.card.metadata["action_handler"] != nil
    has_brain_dump = assigns.card.metadata["action_handler"]["brain_dump"] != nil

    assigns =
      assign(assigns, items: items, brain_dump: brain_dump, has_handler: has_handler, has_brain_dump: has_brain_dump)

    ~H"""
    <.signal_card_frame card={@card}>
      <%!-- Todos --%>
      <p class="text-xs t-dim uppercase tracking-wider font-semibold mb-1">what's happening</p>
      <div class="space-y-1.5">
        <%= for {item, idx} <- Enum.with_index(@items) do %>
          <label class="flex items-center gap-2 text-sm cursor-pointer">
            <input
              type="checkbox"
              checked={item["checked"]}
              phx-click={if @has_handler, do: "pane_action", else: "toggle_checklist_item"}
              phx-value-card-id={@card.id}
              phx-value-action="toggle"
              phx-value-index={idx}
              phx-value-text={item["text"]}
              class="rounded border-input"
            />
            <span class={if item["checked"], do: "line-through text-muted-foreground"}>
              {item["text"]}
            </span>
          </label>
        <% end %>
      </div>
      <.pane_add_input :if={@has_handler && @card.metadata["action_handler"]["add"]} card={@card} />

      <%!-- Brain dump --%>
      <%= if @has_brain_dump do %>
        <div class="mt-4 pt-3 border-t border-border">
          <p class="text-xs t-dim uppercase tracking-wider font-semibold mb-1">brain dump</p>
          <%= if @brain_dump != [] do %>
            <ul class="space-y-1 mb-2">
              <%= for item <- @brain_dump do %>
                <li class="text-sm t-muted pl-2 border-l-2 border-muted">{item}</li>
              <% end %>
            </ul>
          <% end %>
          <.pane_action_input card={@card} action="brain_dump" placeholder="dump a thought..." />
        </div>
      <% end %>

      <.pane_refresh :if={@card.metadata["action_handler"]["refresh"]} card={@card} />
    </.signal_card_frame>
    """
  end

  def signal_card(%{card: %{type: "meeting"}} = assigns) do
    attendees = assigns.card.metadata["attendees"] || []
    agenda = assigns.card.metadata["agenda"] || []
    assigns = assign(assigns, attendees: attendees, agenda: agenda)

    ~H"""
    <.signal_card_frame card={@card}>
      <.md_body body={@card.body} />
      <%= if @attendees != [] do %>
        <div class="flex flex-wrap gap-1 mt-2">
          <%= for a <- @attendees do %>
            <.badge variant="outline" class="text-xs">{a}</.badge>
          <% end %>
        </div>
      <% end %>
      <%= if @agenda != [] do %>
        <ul class="text-sm text-muted-foreground mt-2 list-disc pl-4">
          <%= for item <- @agenda do %>
            <li>{item}</li>
          <% end %>
        </ul>
      <% end %>
    </.signal_card_frame>
    """
  end

  def signal_card(%{card: %{type: "alert"}} = assigns) do
    ~H"""
    <div class="rounded-lg border-2 border-destructive/50 bg-destructive/5 p-5 space-y-2">
      <.signal_card_header card={@card} />
      <.md_body body={@card.body} />
      <.signal_card_actions card={@card} />
    </div>
    """
  end

  def signal_card(%{card: %{type: "link"}} = assigns) do
    url = assigns.card.metadata["url"] || ""
    has_refresh = get_in(assigns.card.metadata, ["action_handler", "refresh"]) != nil
    assigns = assign(assigns, url: url, has_refresh: has_refresh)

    ~H"""
    <.signal_card_frame card={@card}>
      <.md_body body={@card.body} />
      <%= if @url != "" do %>
        <a
          href={@url}
          target="_blank"
          rel="noopener"
          class="text-sm text-primary hover:underline truncate block mt-1"
        >
          {@url}
        </a>
      <% end %>
      <.pane_refresh :if={@has_refresh} card={@card} />
    </.signal_card_frame>
    """
  end

  def signal_card(%{card: %{type: "proposal"}} = assigns) do
    ~H"""
    <.signal_card_frame card={@card}>
      <.md_body body={@card.body} />
      <div class="flex gap-2 mt-3">
        <.button size="sm" variant="outline" phx-click="approve_proposal" phx-value-card-id={@card.id}>
          Approve
        </.button>
        <.button size="sm" variant="ghost" phx-click="reject_proposal" phx-value-card-id={@card.id}>
          Reject
        </.button>
      </div>
    </.signal_card_frame>
    """
  end

  def signal_card(%{card: %{type: "augury"}} = assigns) do
    ~H"""
    <div class="rounded-xl border-2 border-primary/20 bg-primary/5 p-6 space-y-3">
      <div class="flex items-start justify-between gap-4">
        <div>
          <span class="text-xs font-semibold uppercase tracking-widest text-primary/60">
            The Augury
          </span>
          <h2 class="text-lg font-semibold mt-0.5">{@card.title}</h2>
        </div>
        <div class="flex gap-2 shrink-0">
          <.signal_card_actions card={@card} />
        </div>
      </div>
      <.md_body body={@card.body} />
    </div>
    """
  end

  def signal_card(%{card: %{type: "briefing"}} = assigns) do
    ~H"""
    <.signal_card_frame card={@card}>
      <.md_body body={@card.body} />
    </.signal_card_frame>
    """
  end

  def signal_card(%{card: %{type: "action_list"}} = assigns) do
    items = assigns.card.metadata["items"] || []
    action_labels = assigns.card.metadata["action_labels"] || %{}
    approve_label = action_labels["approve"] || "Approve"
    reject_label = action_labels["reject"] || "Reject"
    assigns = assign(assigns, items: items, approve_label: approve_label, reject_label: reject_label)

    ~H"""
    <.signal_card_frame card={@card}>
      <div class="space-y-2">
        <%= for item <- @items do %>
          <div class={[
            "flex items-center justify-between gap-3 rounded-md border p-3 text-sm",
            item["status"] == "approved" && "bg-green-50 dark:bg-green-950/20",
            item["status"] == "rejected" && "bg-red-50 dark:bg-red-950/20 opacity-60"
          ]}>
            <div>
              <div class="font-medium">{item["label"]}</div>
              <%= if item["detail"] do %>
                <div class="text-xs text-muted-foreground">{item["detail"]}</div>
              <% end %>
            </div>
            <%= if item["status"] == "pending" do %>
              <div class="flex gap-1.5 shrink-0">
                <.button
                  size="sm"
                  variant="outline"
                  phx-click="action_list_approve"
                  phx-value-card-id={@card.id}
                  phx-value-item-id={item["id"]}
                >
                  {@approve_label}
                </.button>
                <.button
                  size="sm"
                  variant="ghost"
                  phx-click="action_list_reject"
                  phx-value-card-id={@card.id}
                  phx-value-item-id={item["id"]}
                >
                  {@reject_label}
                </.button>
              </div>
            <% else %>
              <.badge variant={if item["status"] == "approved", do: "default", else: "secondary"}>
                {item["status"]}
              </.badge>
            <% end %>
          </div>
        <% end %>
      </div>
    </.signal_card_frame>
    """
  end

  def signal_card(%{card: %{type: "table"}} = assigns) do
    columns = assigns.card.metadata["columns"] || []
    rows = assigns.card.metadata["rows"] || []
    assigns = assign(assigns, columns: columns, rows: rows)

    ~H"""
    <.signal_card_frame card={@card}>
      <.md_body body={@card.body} />
      <%= if @columns != [] do %>
        <div class="overflow-x-auto mt-2">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b">
                <%= for col <- @columns do %>
                  <th class="text-left py-1.5 px-2 font-medium text-muted-foreground">{col}</th>
                <% end %>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @rows do %>
                <tr class="border-b last:border-0">
                  <%= for col <- @columns do %>
                    <td class="py-1.5 px-2">{row[col] || ""}</td>
                  <% end %>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </.signal_card_frame>
    """
  end

  def signal_card(%{card: %{type: "media"}} = assigns) do
    thumbnail = assigns.card.metadata["thumbnail"] || assigns.card.metadata["url"]
    caption = assigns.card.metadata["caption"] || ""
    assigns = assign(assigns, thumbnail: thumbnail, caption: caption)

    ~H"""
    <.signal_card_frame card={@card}>
      <%= if @thumbnail do %>
        <img src={@thumbnail} alt={@card.title} class="rounded-md max-h-64 object-cover w-full" />
      <% end %>
      <%= if @caption != "" do %>
        <p class="text-sm text-muted-foreground mt-1">{@caption}</p>
      <% end %>
      <.md_body body={@card.body} />
    </.signal_card_frame>
    """
  end

  def signal_card(%{card: %{type: "metric"}} = assigns) do
    value = assigns.card.metadata["value"] || "—"
    trend = assigns.card.metadata["trend"]

    trend_icon =
      case trend do
        "up" -> "↑"
        "down" -> "↓"
        "flat" -> "→"
        _ -> nil
      end

    trend_color =
      case trend do
        "up" -> "text-green-600 dark:text-green-400"
        "down" -> "text-red-600 dark:text-red-400"
        _ -> "text-muted-foreground"
      end

    assigns = assign(assigns, value: value, trend_icon: trend_icon, trend_color: trend_color)

    ~H"""
    <.signal_card_frame card={@card}>
      <div class="flex items-baseline gap-2">
        <span class="text-3xl font-bold tracking-tight">{@value}</span>
        <%= if @trend_icon do %>
          <span class={"text-lg font-semibold " <> @trend_color}>{@trend_icon}</span>
        <% end %>
      </div>
      <.md_body body={@card.body} />
    </.signal_card_frame>
    """
  end

  def signal_card(%{card: %{type: "notepad"}} = assigns) do
    ~H"""
    <.signal_card_frame card={@card}>
      <.md_body body={@card.body} />
      <form phx-submit="pane_action" class="mt-2">
        <input type="hidden" name="card-id" value={@card.id} />
        <input type="hidden" name="action" value="append" />
        <div class="flex gap-2">
          <input
            type="text"
            name="value"
            placeholder="Add a note..."
            class="flex-1 h-8 text-sm border border-input rounded px-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
          />
          <.button type="submit" size="sm" variant="outline">Add</.button>
        </div>
      </form>
      <.pane_refresh :if={@card.metadata["action_handler"]["refresh"]} card={@card} />
    </.signal_card_frame>
    """
  end

  def signal_card(%{card: %{type: "freeform"}} = assigns) do
    ~H"""
    <.signal_card_frame card={@card}>
      <.md_body body={@card.body} />
    </.signal_card_frame>
    """
  end

  # Fallback
  def signal_card(assigns) do
    ~H"""
    <.signal_card_frame card={@card}>
      <.md_body body={@card.body} />
    </.signal_card_frame>
    """
  end

  # ---------------------------------------------------------------------------
  # Pane interaction sub-components
  # ---------------------------------------------------------------------------

  attr :card, :map, required: true

  defp pane_refresh(assigns) do
    ~H"""
    <div class="flex justify-end mt-2">
      <.button
        type="button"
        size="sm"
        variant="ghost"
        phx-click="pane_action"
        phx-value-card-id={@card.id}
        phx-value-action="refresh"
        class="text-xs"
      >
        Refresh
      </.button>
    </div>
    """
  end

  attr :card, :map, required: true
  attr :action, :string, required: true
  attr :placeholder, :string, default: "Add..."

  defp pane_action_input(assigns) do
    ~H"""
    <div
      class="flex gap-2"
      id={"pane-#{@action}-#{@card.id}"}
      phx-hook="PaneAddInput"
      data-card-id={@card.id}
      data-action={@action}
    >
      <input
        type="text"
        placeholder={@placeholder}
        class="flex-1 h-7 text-xs border border-input rounded px-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
      />
      <.button type="button" size="sm" variant="outline" class="text-xs h-7">Add</.button>
    </div>
    """
  end

  attr :card, :map, required: true

  defp pane_add_input(assigns) do
    ~H"""
    <div
      class="flex gap-2 mt-2"
      id={"pane-add-#{@card.id}"}
      phx-hook="PaneAddInput"
      data-card-id={@card.id}
    >
      <input
        type="text"
        placeholder="Add item..."
        class="flex-1 h-7 text-xs border border-input rounded px-2 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
      />
      <.button type="button" size="sm" variant="outline" class="text-xs h-7">Add</.button>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Shared sub-components
  # ---------------------------------------------------------------------------

  attr :card, :map, required: true
  slot :inner_block, required: true

  defp signal_card_frame(assigns) do
    ~H"""
    <.card class="p-5 space-y-2">
      <.signal_card_header card={@card} />
      {render_slot(@inner_block)}
      <.signal_card_actions card={@card} />
    </.card>
    """
  end

  defp signal_card_header(assigns) do
    tags = Map.get(assigns.card, :tags, []) || []
    cluster = Map.get(assigns.card, :cluster_name, nil)
    icon = type_icon(assigns.card.type)
    assigns = assign(assigns, tags: tags, cluster: cluster, type_icon: icon)

    ~H"""
    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center gap-2 min-w-0 flex-wrap">
        <%= if @type_icon do %>
          <span class="text-sm" title={@card.type}>{@type_icon}</span>
        <% end %>
        <span class="font-medium truncate">{@card.title}</span>
        <%= if @cluster do %>
          <.badge variant="outline" class={"text-[10px] shrink-0 " <> cluster_color(@cluster)}>
            {@cluster}
          </.badge>
        <% end %>
        <.badge variant="outline" class="text-xs shrink-0">{@card.type}</.badge>
        <%= if @card.pinned do %>
          <span class="text-xs text-muted-foreground shrink-0" title="pinned">pinned</span>
        <% end %>
        <%= for tag <- @tags do %>
          <.badge variant="outline" class={"text-[10px] shrink-0 " <> tag_color(tag)}>
            {tag}
          </.badge>
        <% end %>
      </div>
    </div>
    """
  end

  @tag_colors %{
    "tech" => "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300",
    "urgent" => "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300",
    "meeting" => "bg-purple-100 text-purple-700 dark:bg-purple-900 dark:text-purple-300",
    "todo" => "bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300",
    "idea" => "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300"
  }

  defp tag_color(tag) do
    Map.get(@tag_colors, tag, "bg-muted text-muted-foreground")
  end

  defp type_icon("briefing"), do: "📜"
  defp type_icon("checklist"), do: "☑️"
  defp type_icon("action_list"), do: "⚖️"
  defp type_icon("table"), do: "📊"
  defp type_icon("media"), do: "🖼️"
  defp type_icon("metric"), do: "📈"
  defp type_icon("notepad"), do: "📝"
  defp type_icon("freeform"), do: "✏️"
  defp type_icon(_), do: nil

  defp cluster_color("tech"), do: "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300"
  defp cluster_color("lifestyle"), do: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300"
  defp cluster_color("business"), do: "bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300"
  defp cluster_color(_), do: ""

  defp signal_card_actions(%{card: %{pin_slug: slug}} = assigns) when is_binary(slug) and slug != "" do
    # Pane cards (owned by a rumination via pin_slug) — no destructive actions
    ~H"""
    <div class="flex gap-1 justify-end">
      <.button
        type="button"
        variant="ghost"
        size="sm"
        phx-click="toggle_pin"
        phx-value-card-id={@card.id}
      >
        {if @card.pinned, do: "Unpin", else: "Pin"}
      </.button>
    </div>
    """
  end

  defp signal_card_actions(assigns) do
    ~H"""
    <div class="flex gap-1 justify-end">
      <.button
        type="button"
        variant="ghost"
        size="sm"
        phx-click="toggle_pin"
        phx-value-card-id={@card.id}
      >
        {if @card.pinned, do: "Unpin", else: "Pin"}
      </.button>
      <.button
        type="button"
        variant="ghost"
        size="sm"
        phx-click="archive_card"
        phx-value-card-id={@card.id}
      >
        Archive
      </.button>
      <.button
        type="button"
        variant="ghost"
        size="sm"
        phx-click="dismiss_card"
        phx-value-card-id={@card.id}
      >
        Dismiss
      </.button>
      <.button
        type="button"
        variant="ghost"
        size="sm"
        phx-click="delete_card"
        phx-value-card-id={@card.id}
        data-confirm="Delete this card?"
      >
        Delete
      </.button>
    </div>
    """
  end

  defp md_body(assigns) do
    ~H"""
    <%= if @body && @body != "" do %>
      <div class="prose prose-sm dark:prose-invert max-w-none">
        {Phoenix.HTML.raw(ExCortexWeb.Markdown.render(@body))}
      </div>
    <% end %>
    """
  end
end
