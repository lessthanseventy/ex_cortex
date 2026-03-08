defmodule ExCellenceServerWeb.GuildHallLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import SaladUI.Badge

  alias Excellence.Schemas.Member
  alias ExCellenceServer.Quests
  alias ExCellenceServer.Quests.Campaign
  alias ExCellenceServer.Quests.Quest
  alias ExCellenceServer.Sources.Book
  alias ExCellenceServer.Sources.Source

  @charters %{
    "Content Moderation" => Excellence.Charters.ContentModeration,
    "Code Review" => Excellence.Charters.CodeReview,
    "Risk Assessment" => Excellence.Charters.RiskAssessment,
    "Accessibility Review" => Excellence.Charters.AccessibilityReview,
    "Performance Audit" => Excellence.Charters.PerformanceAudit,
    "Incident Triage" => Excellence.Charters.IncidentTriage,
    "Contract Review" => Excellence.Charters.ContractReview,
    "Dependency Audit" => Excellence.Charters.DependencyAudit
  }

  @post_install_redirect "/stacks"

  @impl true
  def mount(_params, _session, socket) do
    guilds =
      Enum.map(@charters, fn {_name, mod} ->
        meta = mod.metadata()

        %{
          name: meta.name,
          description: meta.description,
          roles: Enum.map(meta.roles, & &1.name),
          strategy: inspect(meta.strategy)
        }
      end)

    current = current_guild_name()

    {:ok,
     assign(socket,
       page_title: "Guild Hall",
       guilds: guilds,
       current_guild: current,
       confirming: nil
     )}
  end

  @impl true
  def handle_event("select_guild", %{"guild" => guild_name}, socket) do
    if guild_name == socket.assigns.current_guild do
      {:noreply, put_flash(socket, :info, "#{guild_name} Guild is already active.")}
    else
      {:noreply, assign(socket, confirming: guild_name)}
    end
  end

  @impl true
  def handle_event("confirm_install", %{"guild" => guild_name}, socket) do
    case Map.get(@charters, guild_name) do
      nil ->
        {:noreply, put_flash(socket, :error, "Guild not found")}

      mod ->
        import Ecto.Query

        ExCellenceServer.Repo.delete_all(from(r in ExCellenceServer.Quests.CampaignRun))

        ExCellenceServer.Repo.delete_all(from(r in ExCellenceServer.Quests.QuestRun))

        ExCellenceServer.Repo.delete_all(from(c in Campaign))
        ExCellenceServer.Repo.delete_all(from(q in Quest))
        ExCellenceServer.Repo.delete_all(from(r in Member))
        ExCellenceServer.Repo.delete_all(from(s in Source))

        install_guild(mod)
        install_quests(mod)
        install_campaigns(mod)
        create_default_sources(guild_name)

        {:noreply,
         socket
         |> assign(confirming: nil)
         |> put_flash(:info, "#{guild_name} Guild installed!")
         |> push_navigate(to: @post_install_redirect)}
    end
  end

  @impl true
  def handle_event("cancel_install", _params, socket) do
    {:noreply, assign(socket, confirming: nil)}
  end

  @impl true
  def handle_event("build_own_guild", _, socket) do
    import Ecto.Query

    ExCellenceServer.Repo.delete_all(from(r in Member))
    ExCellenceServer.Repo.delete_all(from(q in Quest))
    ExCellenceServer.Repo.delete_all(from(c in Campaign))

    {:noreply,
     socket
     |> assign(current_guild: nil, confirming: nil)
     |> put_flash(:info, "Blank guild ready. Add members and quests to get started.")
     |> push_navigate(to: "/members")}
  end

  defp install_guild(mod) do
    resource_defs = mod.resource_definitions()

    Enum.each(resource_defs, fn attrs ->
      %Member{}
      |> Member.changeset(attrs)
      |> ExCellenceServer.Repo.insert(on_conflict: :nothing)
    end)
  end

  defp install_quests(mod) do
    if function_exported?(mod, :quest_definitions, 0) do
      Enum.each(mod.quest_definitions(), fn attrs ->
        Quests.create_quest(attrs)
      end)
    end
  end

  defp install_campaigns(mod) do
    if function_exported?(mod, :campaign_definitions, 0) do
      quest_by_name = Map.new(Quests.list_quests(), &{&1.name, &1.id})

      Enum.each(mod.campaign_definitions(), fn attrs ->
        steps =
          Enum.map(attrs.steps, fn step ->
            %{"quest_id" => Map.get(quest_by_name, step["quest_name"]), "flow" => step["flow"]}
          end)

        Quests.create_campaign(Map.put(attrs, :steps, steps))
      end)
    end
  end

  defp create_default_sources(guild_name) do
    books = Book.for_guild(guild_name)

    Enum.each(books, fn book ->
      %Source{}
      |> Source.changeset(%{
        source_type: book.source_type,
        config: book.default_config,
        book_id: book.id,
        status: "paused"
      })
      |> ExCellenceServer.Repo.insert()
    end)
  end

  defp current_guild_name do
    import Ecto.Query

    names =
      ExCellenceServer.Repo.all(from(r in Member, where: r.type == "role", select: r.name))

    Enum.find_value(@charters, fn {_name, mod} ->
      meta = mod.metadata()
      role_names = Enum.map(meta.roles, & &1.name)

      if Enum.all?(role_names, &(&1 in names)) do
        meta.name
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold">Guild Hall</h1>
        <p class="text-muted-foreground mt-1">
          Choose your guild. Installing a new guild replaces the current one.
        </p>
      </div>

      <div class="space-y-2">
        <%= for guild <- @guilds do %>
          <div class={[
            "flex items-center justify-between rounded-lg border p-4",
            @current_guild == guild.name && "border-primary bg-accent/50"
          ]}>
            <div class="space-y-1">
              <div class="flex items-center gap-2">
                <span class="font-semibold">{guild.name} Guild</span>
                <%= if @current_guild == guild.name do %>
                  <.badge variant="default">Active</.badge>
                <% end %>
              </div>
              <p class="text-sm text-muted-foreground">{guild.description}</p>
              <div class="flex flex-wrap gap-1 mt-1">
                <%= for role <- guild.roles do %>
                  <.badge variant="outline">{role}</.badge>
                <% end %>
              </div>
            </div>
            <div class="ml-4 shrink-0">
              <%= if @confirming == guild.name do %>
                <div class="flex gap-2">
                  <.button
                    variant="destructive"
                    size="sm"
                    phx-click="confirm_install"
                    phx-value-guild={guild.name}
                  >
                    Confirm
                  </.button>
                  <.button variant="outline" size="sm" phx-click="cancel_install">
                    Cancel
                  </.button>
                </div>
              <% else %>
                <.button
                  variant={if @current_guild == guild.name, do: "outline", else: "default"}
                  size="sm"
                  phx-click="select_guild"
                  phx-value-guild={guild.name}
                >
                  {if @current_guild == guild.name, do: "Active", else: "Install"}
                </.button>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <div class="flex items-center justify-between rounded-lg border border-dashed p-4 mt-4">
        <div class="space-y-1">
          <span class="font-semibold">Build Your Own Guild</span>
          <p class="text-sm text-muted-foreground">
            Start from scratch — add your own members and quests.
          </p>
        </div>
        <.button variant="outline" size="sm" phx-click="build_own_guild">
          Start Fresh
        </.button>
      </div>
    </div>
    """
  end
end
