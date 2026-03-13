defmodule ExCaliburWeb.TownSquareLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge

  alias ExCalibur.Quests
  alias ExCalibur.Quests.Quest
  alias ExCalibur.Quests.Step
  alias ExCalibur.Schemas.Member
  alias ExCalibur.Settings
  alias ExCalibur.Sources.Book
  alias ExCalibur.Sources.Source

  @charters %{
    "Content Moderation" => ExCalibur.Charters.ContentModeration,
    "Code Review" => ExCalibur.Charters.CodeReview,
    "Risk Assessment" => ExCalibur.Charters.RiskAssessment,
    "Accessibility Review" => ExCalibur.Charters.AccessibilityReview,
    "Performance Audit" => ExCalibur.Charters.PerformanceAudit,
    "Incident Triage" => ExCalibur.Charters.IncidentTriage,
    "Contract Review" => ExCalibur.Charters.ContractReview,
    "Dependency Audit" => ExCalibur.Charters.DependencyAudit,
    "Quality Collective" => ExCalibur.Charters.QualityCollective,
    "Platform Guild" => ExCalibur.Charters.PlatformGuild,
    "The Skeptics" => ExCalibur.Charters.TheSkeptics,
    "Product Intelligence" => ExCalibur.Charters.ProductIntelligence,
    "Creative Studio" => ExCalibur.Charters.CreativeStudio,
    "Everyday Council" => ExCalibur.Charters.EverydayCouncil,
    "Tech Dispatch" => ExCalibur.Charters.TechDispatch,
    "Sports Corner" => ExCalibur.Charters.SportsCorner,
    "Market Signals" => ExCalibur.Charters.MarketSignals,
    "Culture Desk" => ExCalibur.Charters.CultureDesk,
    "Science Watch" => ExCalibur.Charters.ScienceWatch,
    "Dev Team" => ExCalibur.Charters.DevTeam
  }

  def charters, do: @charters

  @post_install_redirect "/guild-hall"

  @impl true
  def mount(_params, _session, socket) do
    banner = Settings.get_banner()

    guilds =
      Enum.map(@charters, fn {_name, mod} ->
        meta = mod.metadata()

        %{
          name: meta.name,
          banner: meta.banner,
          description: meta.description,
          roles: Enum.map(meta.roles, & &1.name),
          strategy: inspect(meta.strategy)
        }
      end)

    filtered_guilds =
      if banner do
        banner_atom = String.to_existing_atom(banner)
        Enum.filter(guilds, fn g -> g.banner == banner_atom end)
      else
        guilds
      end

    current = current_guild_name()

    {:ok,
     assign(socket,
       page_title: "Town Square",
       banner: banner,
       guilds: guilds,
       filtered_guilds: filtered_guilds,
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

        ExCalibur.Repo.delete_all(from(r in ExCalibur.Quests.QuestRun))

        ExCalibur.Repo.delete_all(from(r in ExCalibur.Quests.StepRun))

        ExCalibur.Repo.delete_all(from(q in Quest))
        ExCalibur.Repo.delete_all(from(s in Step))
        ExCalibur.Repo.delete_all(from(r in Member))
        ExCalibur.Repo.delete_all(from(s in Source))

        banner = mod.metadata().banner
        Settings.set_banner(to_string(banner))
        install_guild(mod)
        install_steps(mod)
        install_quests(mod)
        create_default_sources(guild_name, banner)
        post_install(guild_name)

        flash_msg =
          if guild_name == "Dev Team",
            do: "Dev Team installed! Set your repo in Stacks to activate the GitHub issue watcher.",
            else: "#{guild_name} Guild installed!"

        {:noreply,
         socket
         |> assign(confirming: nil)
         |> put_flash(:info, flash_msg)
         |> push_navigate(to: @post_install_redirect)}
    end
  end

  @impl true
  def handle_event("cancel_install", _params, socket) do
    {:noreply, assign(socket, confirming: nil)}
  end

  @impl true
  def handle_event("select_banner", %{"banner" => banner}, socket) do
    {:ok, _} = Settings.set_banner(banner)
    banner_atom = String.to_existing_atom(banner)
    filtered = Enum.filter(socket.assigns.guilds, fn g -> g.banner == banner_atom end)

    {:noreply,
     socket
     |> assign(banner: banner, filtered_guilds: filtered)
     |> put_flash(:info, "Flying under the #{String.capitalize(banner)} banner!")}
  end

  @impl true
  def handle_event("reset_banner", _, socket) do
    Settings.set_banner(nil)

    {:noreply, assign(socket, banner: nil, filtered_guilds: socket.assigns.guilds)}
  end

  @impl true
  def handle_event("build_own_guild", _, socket) do
    import Ecto.Query

    ExCalibur.Repo.delete_all(from(r in Member))
    ExCalibur.Repo.delete_all(from(q in Quest))
    ExCalibur.Repo.delete_all(from(s in Step))

    {:noreply,
     socket
     |> assign(current_guild: nil, confirming: nil)
     |> put_flash(:info, "Blank guild ready. Add members and quests to get started.")
     |> push_navigate(to: ~p"/guild-hall")}
  end

  defp install_guild(mod) do
    resource_defs = mod.resource_definitions()

    Enum.each(resource_defs, fn attrs ->
      %Member{}
      |> Member.changeset(attrs)
      |> ExCalibur.Repo.insert(on_conflict: :nothing)
    end)
  end

  defp install_steps(mod) do
    if function_exported?(mod, :quest_definitions, 0) do
      Enum.each(mod.quest_definitions(), fn attrs ->
        Quests.create_step(attrs)
      end)
    end
  end

  defp install_quests(mod) do
    if function_exported?(mod, :campaign_definitions, 0) do
      step_by_name = Map.new(Quests.list_steps(), &{&1.name, &1.id})

      Enum.each(mod.campaign_definitions(), fn attrs ->
        steps = Enum.map(attrs.steps, &resolve_quest_step(&1, step_by_name))
        Quests.create_quest(Map.put(attrs, :steps, steps))
      end)
    end
  end

  defp resolve_quest_step(step, step_by_name) do
    %{"step_id" => Map.get(step_by_name, step["quest_name"] || step["step_name"]), "flow" => step["flow"]}
  end

  defp post_install("Dev Team") do
    require Logger

    case ExCalibur.SelfImprovement.QuestSeed.seed() do
      {:ok, result} ->
        Logger.info("[TownSquare] QuestSeed succeeded: #{inspect(Map.keys(result))}")

      {:error, reason} ->
        Logger.error("[TownSquare] QuestSeed failed: #{inspect(reason)}")

      other ->
        Logger.warning("[TownSquare] QuestSeed unexpected: #{inspect(other)}")
    end
  end

  defp post_install(_guild_name), do: :ok

  defp create_default_sources(guild_name, banner) do
    guild_books = Book.for_guild(guild_name)
    banner_books = if banner, do: Book.for_banner(banner), else: []
    books = Enum.uniq_by(guild_books ++ banner_books, & &1.id)

    source_ids =
      Enum.flat_map(books, fn book ->
        case %Source{}
             |> Source.changeset(%{
               source_type: book.source_type,
               config: book.default_config,
               book_id: book.id,
               status: "paused"
             })
             |> ExCalibur.Repo.insert() do
          {:ok, source} -> [to_string(source.id)]
          _ -> []
        end
      end)

    if source_ids != [] do
      Quests.list_steps()
      |> Enum.filter(&(&1.trigger == "source"))
      |> Enum.each(&Quests.update_step(&1, %{source_ids: source_ids}))
    end
  end

  defp current_guild_name do
    import Ecto.Query

    names =
      ExCalibur.Repo.all(from(r in Member, where: r.type == "role", select: r.name))

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
    <div class="space-y-8">
      <%= if @banner == nil do %>
        <div class="max-w-4xl mx-auto py-12">
          <h1 class="text-2xl font-bold text-center mb-2">Choose Your Banner</h1>
          <p class="text-muted-foreground text-center mb-8">
            Pick your domain to see relevant guilds, quests, and tools.
          </p>
          <div class="grid grid-cols-3 gap-6">
            <%= for {name, desc, icon} <- [
              {"tech", "Code review, security audits, incident triage, and developer tooling.", "⚔️"},
              {"lifestyle", "Content curation, creative projects, sports, culture, and science.", "🛡️"},
              {"business", "Contract review, risk assessment, market analysis, and hiring.", "📜"}
            ] do %>
              <button
                phx-click="select_banner"
                phx-value-banner={name}
                class="rounded-lg border-2 border-muted p-6 text-left hover:border-foreground transition-colors"
              >
                <div class="text-3xl mb-3">{icon}</div>
                <div class="font-bold text-lg capitalize mb-1">{name}</div>
                <div class="text-sm text-muted-foreground">{desc}</div>
              </button>
            <% end %>
          </div>
        </div>
      <% else %>
        <div>
          <div class="flex items-start justify-between">
            <h1 class="text-3xl font-bold tracking-tight">Town Square</h1>
            <button
              phx-click="reset_banner"
              class="text-xs text-muted-foreground hover:text-foreground transition-colors"
            >
              Change banner
            </button>
          </div>
          <p class="text-muted-foreground mt-1.5">
            Choose your guild. Installing a new guild replaces the current one.
          </p>
          <%= if @current_guild do %>
            <p class="text-sm text-muted-foreground">
              Current guild: {@current_guild}
            </p>
          <% end %>
        </div>

        <div class="space-y-3">
          <%= for guild <- @filtered_guilds do %>
            <div class={[
              "flex flex-col gap-4 rounded-lg border p-5 sm:flex-row sm:items-center sm:justify-between",
              @current_guild == guild.name && "border-primary bg-accent/50"
            ]}>
              <div class="space-y-1.5">
                <div class="flex items-center gap-2">
                  <span class="font-semibold">{guild.name} Guild</span>
                  <%= if @current_guild == guild.name do %>
                    <.badge variant="default">Active</.badge>
                  <% end %>
                </div>
                <p class="text-sm text-muted-foreground">{guild.description}</p>
                <div class="flex flex-wrap gap-1.5 mt-1">
                  <%= for role <- guild.roles do %>
                    <.badge variant="outline">{role}</.badge>
                  <% end %>
                </div>
              </div>
              <div class="ml-4 shrink-0">
                <%= if @confirming == guild.name do %>
                  <div class="flex gap-2">
                    <.button
                      type="button"
                      variant="destructive"
                      size="sm"
                      phx-click="confirm_install"
                      phx-value-guild={guild.name}
                    >
                      Confirm
                    </.button>
                    <.button type="button" variant="outline" size="sm" phx-click="cancel_install">
                      Cancel
                    </.button>
                  </div>
                <% else %>
                  <.button
                    type="button"
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

        <div class="flex flex-col gap-4 rounded-lg border border-dashed p-5 mt-2 sm:flex-row sm:items-center sm:justify-between">
          <div class="space-y-1">
            <span class="font-semibold">Build Your Own Guild</span>
            <p class="text-sm text-muted-foreground">
              Start from scratch — add your own members and quests.
            </p>
          </div>
          <.button type="button" variant="outline" size="sm" phx-click="build_own_guild">
            Start Fresh
          </.button>
        </div>
      <% end %>
    </div>
    """
  end
end
