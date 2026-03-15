defmodule ExCortexWeb.TownSquareLive do
  @moduledoc false
  use ExCortexWeb, :live_view

  import SaladUI.Badge

  alias ExCortex.Neurons.Neuron
  alias ExCortex.Senses.Reflex
  alias ExCortex.Senses.Sense
  alias ExCortex.Settings
  alias ExCortex.Thoughts
  alias ExCortex.Thoughts.Synapse
  alias ExCortex.Thoughts.Thought

  @pathways %{
    "Content Moderation" => ExCortex.Pathways.ContentModeration,
    "Code Review" => ExCortex.Pathways.CodeReview,
    "Risk Assessment" => ExCortex.Pathways.RiskAssessment,
    "Accessibility Review" => ExCortex.Pathways.AccessibilityReview,
    "Performance Audit" => ExCortex.Pathways.PerformanceAudit,
    "Incident Triage" => ExCortex.Pathways.IncidentTriage,
    "Contract Review" => ExCortex.Pathways.ContractReview,
    "Dependency Audit" => ExCortex.Pathways.DependencyAudit,
    "Quality Collective" => ExCortex.Pathways.QualityCollective,
    "Platform Cluster" => ExCortex.Pathways.Platform,
    "The Skeptics" => ExCortex.Pathways.Skeptics,
    "Product Intelligence" => ExCortex.Pathways.ProductIntelligence,
    "Creative Studio" => ExCortex.Pathways.CreativeStudio,
    "Everyday Council" => ExCortex.Pathways.EverydayCouncil,
    "Tech Dispatch" => ExCortex.Pathways.TechDispatch,
    "Sports Corner" => ExCortex.Pathways.SportsCorner,
    "Market Signals" => ExCortex.Pathways.MarketSignals,
    "Culture Desk" => ExCortex.Pathways.CultureDesk,
    "Science Watch" => ExCortex.Pathways.ScienceWatch,
    "Dev Team" => ExCortex.Pathways.DevTeam
  }

  def pathways, do: @pathways

  @post_install_redirect "/cluster-hall"

  @impl true
  def mount(_params, _session, socket) do
    banner = Settings.get_banner()

    clusters =
      Enum.map(@pathways, fn {_name, mod} ->
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
        Enum.filter(clusters, fn g -> g.banner == banner_atom end)
      else
        clusters
      end

    current = current_guild_name()

    {:ok,
     assign(socket,
       page_title: "Town Square",
       banner: banner,
       clusters: clusters,
       filtered_guilds: filtered_guilds,
       current_guild: current,
       confirming: nil
     )}
  end

  @impl true
  def handle_event("select_guild", %{"cluster" => guild_name}, socket) do
    if guild_name == socket.assigns.current_guild do
      {:noreply, put_flash(socket, :info, "#{guild_name} Cluster is already active.")}
    else
      {:noreply, assign(socket, confirming: guild_name)}
    end
  end

  @impl true
  def handle_event("confirm_install", %{"cluster" => guild_name}, socket) do
    case Map.get(@pathways, guild_name) do
      nil ->
        {:noreply, put_flash(socket, :error, "Cluster not found")}

      mod ->
        import Ecto.Query

        ExCortex.Repo.delete_all(from(r in ExCortex.Thoughts.Daydream))

        ExCortex.Repo.delete_all(from(r in ExCortex.Thoughts.Impulse))

        ExCortex.Repo.delete_all(from(q in Thought))
        ExCortex.Repo.delete_all(from(s in Synapse))
        ExCortex.Repo.delete_all(from(r in Neuron))
        ExCortex.Repo.delete_all(from(s in Sense))

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
            else: "#{guild_name} Cluster installed!"

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
    filtered = Enum.filter(socket.assigns.clusters, fn g -> g.banner == banner_atom end)

    {:noreply,
     socket
     |> assign(banner: banner, filtered_guilds: filtered)
     |> put_flash(:info, "Flying under the #{String.capitalize(banner)} banner!")}
  end

  @impl true
  def handle_event("reset_banner", _, socket) do
    Settings.set_banner(nil)

    {:noreply, assign(socket, banner: nil, filtered_guilds: socket.assigns.clusters)}
  end

  @impl true
  def handle_event("build_own_guild", _, socket) do
    import Ecto.Query

    ExCortex.Repo.delete_all(from(r in Neuron))
    ExCortex.Repo.delete_all(from(q in Thought))
    ExCortex.Repo.delete_all(from(s in Synapse))

    {:noreply,
     socket
     |> assign(current_guild: nil, confirming: nil)
     |> put_flash(:info, "Blank cluster ready. Add neurons and thoughts to get started.")
     |> push_navigate(to: ~p"/cluster-hall")}
  end

  defp install_guild(mod) do
    resource_defs = mod.resource_definitions()

    Enum.each(resource_defs, fn attrs ->
      %Neuron{}
      |> Neuron.changeset(attrs)
      |> ExCortex.Repo.insert(on_conflict: :nothing)
    end)
  end

  defp install_steps(mod) do
    if function_exported?(mod, :quest_definitions, 0) do
      Enum.each(mod.quest_definitions(), fn attrs ->
        Thoughts.create_synapse(attrs)
      end)
    end
  end

  defp install_quests(mod) do
    if function_exported?(mod, :campaign_definitions, 0) do
      step_by_name = Map.new(Thoughts.list_synapses(), &{&1.name, &1.id})

      Enum.each(mod.campaign_definitions(), fn attrs ->
        steps = Enum.map(attrs.steps, &resolve_quest_step(&1, step_by_name))
        Thoughts.create_thought(Map.put(attrs, :steps, steps))
      end)
    end
  end

  defp resolve_quest_step(step, step_by_name) do
    %{"step_id" => Map.get(step_by_name, step["thought_name"] || step["step_name"]), "flow" => step["flow"]}
  end

  defp post_install("Dev Team") do
    require Logger

    case ExCortex.Neuroplasticity.Seed.seed() do
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
    guild_reflexes = Reflex.for_guild(guild_name)
    banner_reflexes = if banner, do: Reflex.for_banner(banner), else: []
    reflexes = Enum.uniq_by(guild_reflexes ++ banner_reflexes, & &1.id)

    source_ids =
      Enum.flat_map(reflexes, fn reflex ->
        case %Sense{}
             |> Sense.changeset(%{
               source_type: reflex.source_type,
               config: reflex.default_config,
               book_id: reflex.id,
               status: "paused"
             })
             |> ExCortex.Repo.insert() do
          {:ok, source} -> [to_string(source.id)]
          _ -> []
        end
      end)

    if source_ids != [] do
      Thoughts.list_synapses()
      |> Enum.filter(&(&1.trigger == "source"))
      |> Enum.each(&Thoughts.update_synapse(&1, %{source_ids: source_ids}))
    end
  end

  defp current_guild_name do
    import Ecto.Query

    names =
      ExCortex.Repo.all(from(r in Neuron, where: r.type == "role", select: r.name))

    Enum.find_value(@pathways, fn {_name, mod} ->
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
            Pick your domain to see relevant clusters, thoughts, and tools.
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
            Choose your cluster. Installing a new cluster replaces the current one.
          </p>
          <%= if @current_guild do %>
            <p class="text-sm text-muted-foreground">
              Current cluster: {@current_guild}
            </p>
          <% end %>
        </div>

        <div class="space-y-3">
          <%= for cluster <- @filtered_guilds do %>
            <div class={[
              "flex flex-col gap-4 rounded-lg border p-5 sm:flex-row sm:items-center sm:justify-between",
              @current_guild == cluster.name && "border-primary bg-accent/50"
            ]}>
              <div class="space-y-1.5">
                <div class="flex items-center gap-2">
                  <span class="font-semibold">{cluster.name} Cluster</span>
                  <%= if @current_guild == cluster.name do %>
                    <.badge variant="default">Active</.badge>
                  <% end %>
                </div>
                <p class="text-sm text-muted-foreground">{cluster.description}</p>
                <div class="flex flex-wrap gap-1.5 mt-1">
                  <%= for role <- cluster.roles do %>
                    <.badge variant="outline">{role}</.badge>
                  <% end %>
                </div>
              </div>
              <div class="ml-4 shrink-0">
                <%= if @confirming == cluster.name do %>
                  <div class="flex gap-2">
                    <.button
                      type="button"
                      variant="destructive"
                      size="sm"
                      phx-click="confirm_install"
                      phx-value-cluster={cluster.name}
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
                    variant={if @current_guild == cluster.name, do: "outline", else: "default"}
                    size="sm"
                    phx-click="select_guild"
                    phx-value-cluster={cluster.name}
                  >
                    {if @current_guild == cluster.name, do: "Active", else: "Install"}
                  </.button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <div class="flex flex-col gap-4 rounded-lg border border-dashed p-5 mt-2 sm:flex-row sm:items-center sm:justify-between">
          <div class="space-y-1">
            <span class="font-semibold">Build Your Own Cluster</span>
            <p class="text-sm text-muted-foreground">
              Start from scratch — add your own neurons and thoughts.
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
