defmodule ExCellenceServerWeb.StacksLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import SaladUI.Badge
  import SaladUI.Card

  alias ExCellenceServer.Sources.Source
  alias ExCellenceServer.Sources.SourceSupervisor

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExCellenceServer.PubSub, "sources")
      :timer.send_interval(10_000, self(), :refresh)
    end

    {:ok, load_sources(assign(socket, page_title: "Stacks"))}
  end

  @impl true
  def handle_event("resume", %{"id" => id}, socket) do
    source = ExCellenceServer.Repo.get!(Source, id)
    source |> Source.changeset(%{status: "active", error_message: nil}) |> ExCellenceServer.Repo.update!()
    SourceSupervisor.start_source(source)
    {:noreply, load_sources(socket)}
  end

  @impl true
  def handle_event("pause", %{"id" => id}, socket) do
    source = ExCellenceServer.Repo.get!(Source, id)
    source |> Source.changeset(%{status: "paused"}) |> ExCellenceServer.Repo.update!()
    SourceSupervisor.stop_source(id)
    {:noreply, load_sources(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    source = ExCellenceServer.Repo.get!(Source, id)
    SourceSupervisor.stop_source(id)
    ExCellenceServer.Repo.delete!(source)
    {:noreply, load_sources(put_flash(socket, :info, "Source removed from stacks."))}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load_sources(socket)}

  @impl true
  def handle_info(_msg, socket), do: {:noreply, load_sources(socket)}

  defp load_sources(socket) do
    import Ecto.Query

    sources = ExCellenceServer.Repo.all(from(s in Source, order_by: [desc: s.inserted_at]))
    assign(socket, sources: sources)
  end

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
        <.card>
          <.card_content class="pt-6">
            <p class="text-muted-foreground text-sm">
              Your stacks are empty. Browse the <a href="/library" class="underline">Library</a>
              to add books to your guild.
            </p>
          </.card_content>
        </.card>
      <% else %>
        <div class="space-y-4">
          <%= for source <- @sources do %>
            <.card>
              <.card_content class="pt-6">
                <div class="flex items-center justify-between">
                  <div class="space-y-1">
                    <div class="flex items-center gap-2">
                      <span class="font-medium">{source.guild_name} Guild</span>
                      <.badge variant="outline">{source.source_type}</.badge>
                      <.badge variant={status_variant(source.status)}>{source.status}</.badge>
                    </div>
                    <p class="text-sm text-muted-foreground">
                      Last run: {format_time(source.last_run_at)}
                    </p>
                    <%= if source.source_type == "webhook" do %>
                      <p class="text-xs text-muted-foreground font-mono">
                        POST /api/webhooks/{source.id}
                      </p>
                    <% end %>
                    <%= if source.error_message do %>
                      <p class="text-sm text-destructive">{source.error_message}</p>
                    <% end %>
                  </div>
                  <div class="flex gap-2">
                    <%= if source.status == "active" do %>
                      <.button variant="outline" size="sm" phx-click="pause" phx-value-id={source.id}>
                        Pause
                      </.button>
                    <% else %>
                      <.button variant="outline" size="sm" phx-click="resume" phx-value-id={source.id}>
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
              </.card_content>
            </.card>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
