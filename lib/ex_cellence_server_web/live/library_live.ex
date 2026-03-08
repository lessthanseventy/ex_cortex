defmodule ExCellenceServerWeb.LibraryLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import SaladUI.Badge
  import SaladUI.Card

  alias ExCellenceServer.Sources.Book
  alias ExCellenceServer.Sources.Source

  @impl true
  def mount(_params, _session, socket) do
    books = Book.all()
    installed_guilds = installed_guild_names()

    {:ok,
     assign(socket,
       page_title: "Library",
       books: books,
       installed_guilds: installed_guilds,
       adding_book: nil
     )}
  end

  @impl true
  def handle_event("start_add", %{"book-id" => book_id}, socket) do
    {:noreply, assign(socket, adding_book: book_id)}
  end

  @impl true
  def handle_event("cancel_add", _params, socket) do
    {:noreply, assign(socket, adding_book: nil)}
  end

  @impl true
  def handle_event("add_to_guild", %{"book-id" => book_id, "guild" => guild_name}, socket) do
    book = Book.get(book_id)

    case book do
      nil ->
        {:noreply, put_flash(socket, :error, "Book not found")}

      book ->
        %Source{}
        |> Source.changeset(%{
          guild_name: guild_name,
          source_type: book.source_type,
          config: book.default_config,
          status: "paused"
        })
        |> ExCellenceServer.Repo.insert()

        {:noreply,
         socket
         |> put_flash(:info, "#{book.name} added to #{guild_name} Guild. Configure it in the Stacks.")
         |> push_navigate(to: "/stacks")}
    end
  end

  defp installed_guild_names do
    import Ecto.Query

    alias Excellence.Schemas.ResourceDefinition

    charters = ExCellenceServer.Evaluator.charters()
    names = ExCellenceServer.Repo.all(from(r in ResourceDefinition, where: r.type == "role", select: r.name))

    charters
    |> Enum.reduce([], fn {guild_name, mod}, acc ->
      meta = mod.metadata()
      role_names = Enum.map(meta.roles, & &1.name)

      if Enum.all?(role_names, &(&1 in names)) do
        [guild_name | acc]
      else
        acc
      end
    end)
    |> Enum.sort()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold">Library</h1>
        <p class="text-muted-foreground mt-1">
          Browse available books — pre-configured sources of knowledge for your guilds.
        </p>
      </div>

      <%= if @installed_guilds == [] do %>
        <.card>
          <.card_content class="pt-6">
            <p class="text-muted-foreground text-sm">
              No guilds installed yet. Visit the
              <a href="/guild-hall" class="underline">Guild Hall</a>
              to install a guild first.
            </p>
          </.card_content>
        </.card>
      <% end %>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <%= for book <- @books do %>
          <.card>
            <.card_header>
              <div class="flex items-center justify-between">
                <.card_title>{book.name}</.card_title>
                <.badge variant="outline">{book.source_type}</.badge>
              </div>
              <.card_description>{book.description}</.card_description>
            </.card_header>
            <.card_content>
              <%= if book.suggested_guild do %>
                <p class="text-sm text-muted-foreground">
                  Recommended for: <span class="font-medium">{book.suggested_guild} Guild</span>
                </p>
              <% end %>
            </.card_content>
            <.card_footer>
              <%= if @adding_book == book.id do %>
                <div class="flex gap-2 flex-wrap">
                  <%= for guild <- @installed_guilds do %>
                    <.button
                      size="sm"
                      phx-click="add_to_guild"
                      phx-value-book-id={book.id}
                      phx-value-guild={guild}
                    >
                      {guild}
                    </.button>
                  <% end %>
                  <.button variant="outline" size="sm" phx-click="cancel_add">
                    Cancel
                  </.button>
                </div>
              <% else %>
                <.button
                  variant="outline"
                  phx-click="start_add"
                  phx-value-book-id={book.id}
                  disabled={@installed_guilds == []}
                >
                  Add to Guild
                </.button>
              <% end %>
            </.card_footer>
          </.card>
        <% end %>
      </div>
    </div>
    """
  end
end
