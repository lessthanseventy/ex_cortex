defmodule ExCaliburWeb.StacksLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge

  alias ExCalibur.Sources.Book
  alias ExCalibur.Sources.Source
  alias ExCalibur.Sources.SourceSupervisor

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCalibur.PubSub, "sources")
      :timer.send_interval(10_000, self(), :refresh)
    end

    {:ok, load_sources(assign(socket, page_title: "Stacks"))}
  end

  @impl true
  def handle_event("resume", %{"id" => id}, socket) do
    source = ExCalibur.Repo.get!(Source, id)

    source
    |> Source.changeset(%{status: "active", error_message: nil})
    |> ExCalibur.Repo.update!()

    SourceSupervisor.start_source(source)
    {:noreply, load_sources(socket)}
  end

  @impl true
  def handle_event("pause", %{"id" => id}, socket) do
    source = ExCalibur.Repo.get!(Source, id)
    source |> Source.changeset(%{status: "paused"}) |> ExCalibur.Repo.update!()
    SourceSupervisor.stop_source(id)
    {:noreply, load_sources(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    source = ExCalibur.Repo.get!(Source, id)
    SourceSupervisor.stop_source(id)
    ExCalibur.Repo.delete!(source)
    {:noreply, load_sources(put_flash(socket, :info, "Source removed from stacks."))}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load_sources(socket)}

  @impl true
  def handle_info(_msg, socket), do: {:noreply, load_sources(socket)}

  defp load_sources(socket) do
    import Ecto.Query

    sources = ExCalibur.Repo.all(from(s in Source, order_by: [desc: s.inserted_at]))
    assign(socket, sources: sources)
  end

  defp source_name(%Source{book_id: book_id}) when is_binary(book_id) do
    case Book.get(book_id) do
      nil -> book_id
      book -> book.name
    end
  end

  defp source_name(%Source{source_type: type}), do: String.capitalize(type) <> " source"

  defp status_variant("active"), do: "default"
  defp status_variant("paused"), do: "secondary"
  defp status_variant("error"), do: "destructive"
  defp status_variant(_), do: "outline"

  defp format_time(nil), do: "Never"
  defp format_time(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Stacks</h1>
        <a href="/library">
          <.button variant="outline">Browse Library</.button>
        </a>
      </div>

      <%= if @sources == [] do %>
        <div class="rounded-lg border p-4">
          <p class="text-muted-foreground text-sm">
            Your stacks are empty. Browse the <a href="/library" class="underline">Library</a>
            to add scrolls and books.
          </p>
        </div>
      <% else %>
        <div class="space-y-2">
          <%= for source <- @sources do %>
            <div class="flex items-center justify-between rounded-lg border p-4">
              <div class="space-y-1">
                <div class="flex items-center gap-2">
                  <span class="font-medium">{source_name(source)}</span>
                  <.badge variant="outline">{source.source_type}</.badge>
                  <.badge variant={status_variant(source.status)}>{source.status}</.badge>
                </div>
                <p class="text-xs text-muted-foreground">
                  Last run: {format_time(source.last_run_at)}
                </p>
                <%= if source.source_type == "webhook" do %>
                  <p class="text-xs text-muted-foreground font-mono">
                    POST /api/webhooks/{source.id}
                  </p>
                <% end %>
                <%= if source.error_message do %>
                  <p class="text-xs text-destructive">{source.error_message}</p>
                <% end %>
              </div>
              <div class="ml-4 shrink-0 flex gap-2">
                <%= if source.status == "active" do %>
                  <.button
                    variant="outline"
                    size="sm"
                    phx-click="pause"
                    phx-value-id={source.id}
                  >
                    Pause
                  </.button>
                <% else %>
                  <.button
                    variant="outline"
                    size="sm"
                    phx-click="resume"
                    phx-value-id={source.id}
                  >
                    Resume
                  </.button>
                <% end %>
                <.button
                  variant="destructive"
                  size="sm"
                  phx-click="delete"
                  phx-value-id={source.id}
                >
                  Delete
                </.button>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
