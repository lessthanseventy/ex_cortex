defmodule ExCellenceServerWeb.GuildHallLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import SaladUI.Badge
  import SaladUI.Card

  alias Excellence.Schemas.ResourceDefinition

  @templates %{
    "Content Moderation" => Excellence.Templates.ContentModeration,
    "Code Review" => Excellence.Templates.CodeReview,
    "Risk Assessment" => Excellence.Templates.RiskAssessment
  }

  @post_install_redirect "/evaluate"

  @impl true
  def mount(_params, _session, socket) do
    guilds =
      Enum.map(@templates, fn {_name, mod} ->
        meta = mod.metadata()

        %{
          name: meta.name,
          description: meta.description,
          roles: Enum.map(meta.roles, & &1.name),
          strategy: inspect(meta.strategy)
        }
      end)

    installed_names = installed_guild_names()

    {:ok,
     assign(socket,
       page_title: "Guild Hall",
       guilds: guilds,
       installed_names: installed_names,
       confirming_dissolve: nil
     )}
  end

  @impl true
  def handle_event("install_guild", %{"guild" => guild_name}, socket) do
    case Map.get(@templates, guild_name) do
      nil ->
        {:noreply, put_flash(socket, :error, "Guild not found")}

      mod ->
        install_guild(mod)

        {:noreply,
         socket
         |> put_flash(:info, "#{guild_name} Guild installed!")
         |> push_navigate(to: @post_install_redirect)}
    end
  end

  @impl true
  def handle_event("confirm_dissolve", %{"guild" => guild_name}, socket) do
    {:noreply, assign(socket, confirming_dissolve: guild_name)}
  end

  @impl true
  def handle_event("cancel_dissolve", _params, socket) do
    {:noreply, assign(socket, confirming_dissolve: nil)}
  end

  @impl true
  def handle_event("dissolve_and_install", %{"guild" => guild_name}, socket) do
    case Map.get(@templates, guild_name) do
      nil ->
        {:noreply, put_flash(socket, :error, "Guild not found")}

      mod ->
        import Ecto.Query

        ExCellenceServer.Repo.delete_all(from(r in ResourceDefinition))
        install_guild(mod)

        {:noreply,
         socket
         |> put_flash(:info, "All members dissolved. #{guild_name} Guild installed!")
         |> push_navigate(to: @post_install_redirect)}
    end
  end

  defp install_guild(mod) do
    resource_defs = mod.resource_definitions()

    Enum.each(resource_defs, fn attrs ->
      %ResourceDefinition{}
      |> ResourceDefinition.changeset(attrs)
      |> ExCellenceServer.Repo.insert(on_conflict: :nothing)
    end)
  end

  defp installed_guild_names do
    import Ecto.Query

    names = ExCellenceServer.Repo.all(from(r in ResourceDefinition, where: r.type == "role", select: r.name))

    # Check which guilds have all their roles installed
    Enum.reduce(@templates, MapSet.new(), fn {_name, mod}, acc ->
      meta = mod.metadata()
      role_names = Enum.map(meta.roles, & &1.name)

      if Enum.all?(role_names, &(&1 in names)) do
        MapSet.put(acc, meta.name)
      else
        acc
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Guild Hall</h1>
      </div>
      <p class="text-muted-foreground">
        Browse and install pre-built guilds — organizations of agents with specialized expertise.
      </p>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <%= for guild <- @guilds do %>
          <.card>
            <.card_header>
              <div class="flex items-center justify-between">
                <.card_title>{guild.name} Guild</.card_title>
                <%= if MapSet.member?(@installed_names, guild.name) do %>
                  <.badge variant="default">Installed</.badge>
                <% end %>
              </div>
              <.card_description>{guild.description}</.card_description>
            </.card_header>
            <.card_content>
              <div class="space-y-2">
                <p class="text-sm font-medium">Members</p>
                <div class="flex flex-wrap gap-1">
                  <%= for role <- guild.roles do %>
                    <.badge variant="outline">{role}</.badge>
                  <% end %>
                </div>
                <p class="text-sm text-muted-foreground mt-2">Strategy: {guild.strategy}</p>
              </div>
            </.card_content>
            <.card_footer>
              <div class="flex gap-2">
                <%= if @confirming_dissolve == guild.name do %>
                  <.button
                    variant="destructive"
                    phx-click="dissolve_and_install"
                    phx-value-guild={guild.name}
                  >
                    Confirm Dissolve & Install
                  </.button>
                  <.button variant="outline" phx-click="cancel_dissolve">Cancel</.button>
                <% else %>
                  <.button phx-click="install_guild" phx-value-guild={guild.name}>
                    Install Guild
                  </.button>
                  <.button
                    variant="outline"
                    phx-click="confirm_dissolve"
                    phx-value-guild={guild.name}
                  >
                    Dissolve All & Install
                  </.button>
                <% end %>
              </div>
            </.card_footer>
          </.card>
        <% end %>
      </div>
    </div>
    """
  end
end
