defmodule ExCaliburWeb.LibraryLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge

  alias ExCalibur.Sources.Book
  alias ExCalibur.Sources.Source

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Library",
       scrolls: Book.scrolls(),
       books: Book.books()
     )}
  end

  @impl true
  def handle_event("add_to_stacks", %{"book-id" => book_id}, socket) do
    book = Book.get(book_id)

    case book do
      nil ->
        {:noreply, put_flash(socket, :error, "Book not found")}

      book ->
        %Source{}
        |> Source.changeset(%{
          source_type: book.source_type,
          config: book.default_config,
          book_id: book.id,
          status: "paused"
        })
        |> ExCalibur.Repo.insert()

        {:noreply,
         socket
         |> put_flash(:info, "#{book.name} added to your stacks.")
         |> push_navigate(to: "/stacks")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div>
        <h1 class="text-2xl font-bold">Library</h1>
        <p class="text-muted-foreground mt-1">
          Browse scrolls and books — sources of knowledge for your guild.
        </p>
      </div>

      <div>
        <h2 class="text-lg font-semibold mb-1">Scrolls</h2>
        <p class="text-muted-foreground text-sm mb-4">
          Pre-configured feeds — subscribe and start receiving knowledge immediately.
        </p>
        <div class="space-y-2">
          <%= for item <- @scrolls do %>
            <.library_row item={item} />
          <% end %>
        </div>
      </div>

      <div>
        <h2 class="text-lg font-semibold mb-1">Books</h2>
        <p class="text-muted-foreground text-sm mb-4">
          Configurable sources — point them at your own repos, directories, and endpoints.
        </p>
        <div class="space-y-2">
          <%= for item <- @books do %>
            <.library_row item={item} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp library_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between rounded-lg border p-4">
      <div class="space-y-1">
        <div class="flex items-center gap-2">
          <span class="font-medium">{@item.name}</span>
          <.badge variant={if @item.kind == :scroll, do: "default", else: "outline"}>
            {if @item.kind == :scroll, do: "scroll", else: "book"}
          </.badge>
          <.badge variant="secondary">{@item.source_type}</.badge>
          <%= if @item.suggested_guild do %>
            <span class="text-xs text-muted-foreground">{@item.suggested_guild}</span>
          <% end %>
        </div>
        <p class="text-sm text-muted-foreground">{@item.description}</p>
      </div>
      <div class="ml-4 shrink-0">
        <.button
          variant="outline"
          size="sm"
          phx-click="add_to_stacks"
          phx-value-book-id={@item.id}
        >
          Add to Stacks
        </.button>
      </div>
    </div>
    """
  end
end
