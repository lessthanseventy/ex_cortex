defmodule ExCaliburWeb.Components.LodgeCards do
  @moduledoc "Function components for rendering Lodge cards by type."
  use Phoenix.Component

  import SaladUI.Badge
  import SaladUI.Button

  attr :card, :map, required: true

  def lodge_card(%{card: %{type: "note"}} = assigns) do
    ~H"""
    <.card_wrapper card={@card}>
      <.md_body body={@card.body} />
    </.card_wrapper>
    """
  end

  def lodge_card(%{card: %{type: "checklist"}} = assigns) do
    items = assigns.card.metadata["items"] || []
    assigns = assign(assigns, :items, items)

    ~H"""
    <.card_wrapper card={@card}>
      <div class="space-y-1.5">
        <%= for {item, idx} <- Enum.with_index(@items) do %>
          <label class="flex items-center gap-2 text-sm cursor-pointer">
            <input
              type="checkbox"
              checked={item["checked"]}
              phx-click="toggle_checklist_item"
              phx-value-card-id={@card.id}
              phx-value-index={idx}
              class="rounded border-input"
            />
            <span class={if item["checked"], do: "line-through text-muted-foreground"}>
              {item["text"]}
            </span>
          </label>
        <% end %>
      </div>
    </.card_wrapper>
    """
  end

  def lodge_card(%{card: %{type: "meeting"}} = assigns) do
    attendees = assigns.card.metadata["attendees"] || []
    agenda = assigns.card.metadata["agenda"] || []
    assigns = assign(assigns, attendees: attendees, agenda: agenda)

    ~H"""
    <.card_wrapper card={@card}>
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
    </.card_wrapper>
    """
  end

  def lodge_card(%{card: %{type: "alert"}} = assigns) do
    ~H"""
    <div class="rounded-lg border-2 border-destructive/50 bg-destructive/5 p-5 space-y-2">
      <.card_header card={@card} />
      <.md_body body={@card.body} />
      <.card_actions card={@card} />
    </div>
    """
  end

  def lodge_card(%{card: %{type: "link"}} = assigns) do
    url = assigns.card.metadata["url"] || ""
    assigns = assign(assigns, :url, url)

    ~H"""
    <.card_wrapper card={@card}>
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
    </.card_wrapper>
    """
  end

  def lodge_card(%{card: %{type: "proposal"}} = assigns) do
    ~H"""
    <.card_wrapper card={@card}>
      <.md_body body={@card.body} />
      <div class="flex gap-2 mt-3">
        <.button size="sm" variant="outline" phx-click="approve_proposal" phx-value-card-id={@card.id}>
          Approve
        </.button>
        <.button size="sm" variant="ghost" phx-click="reject_proposal" phx-value-card-id={@card.id}>
          Reject
        </.button>
      </div>
    </.card_wrapper>
    """
  end

  def lodge_card(%{card: %{type: "augury"}} = assigns) do
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
          <.button
            type="button"
            variant="outline"
            size="sm"
            phx-click="edit_augury"
            phx-value-card-id={@card.id}
          >
            Edit
          </.button>
          <.card_actions card={@card} />
        </div>
      </div>
      <.md_body body={@card.body} />
    </div>
    """
  end

  # Fallback
  def lodge_card(assigns) do
    ~H"""
    <.card_wrapper card={@card}>
      <.md_body body={@card.body} />
    </.card_wrapper>
    """
  end

  # Shared sub-components

  attr :card, :map, required: true
  slot :inner_block, required: true

  defp card_wrapper(assigns) do
    ~H"""
    <div class="rounded-lg border bg-card p-5 space-y-2">
      <.card_header card={@card} />
      {render_slot(@inner_block)}
      <.card_actions card={@card} />
    </div>
    """
  end

  defp card_header(assigns) do
    tags = Map.get(assigns.card, :tags) || []
    assigns = assign(assigns, :tags, tags)

    ~H"""
    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center gap-2 min-w-0 flex-wrap">
        <span class="font-medium truncate">{@card.title}</span>
        <.badge variant="outline" class="text-xs shrink-0">{@card.type}</.badge>
        <%= if @card.pinned do %>
          <span class="text-xs text-muted-foreground shrink-0" title="pinned">pinned</span>
        <% end %>
        <%= for tag <- @tags do %>
          <span class={[
            "inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-medium",
            tag_color(tag)
          ]}>
            {tag}
          </span>
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

  defp card_actions(assigns) do
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
        {Phoenix.HTML.raw(ExCaliburWeb.Markdown.render(@body))}
      </div>
    <% end %>
    """
  end
end
