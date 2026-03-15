defmodule ExCortexWeb.GuildHallLive do
  @moduledoc false
  use ExCortexWeb, :live_view

  import SaladUI.Badge
  import SaladUI.Button

  alias ExCortex.Clusters
  alias ExCortex.Neurons.Builtin
  alias ExCortex.Neurons.Neuron
  alias ExCortex.Settings

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) and is_nil(Settings.get_banner()) do
      {:ok, push_navigate(socket, to: ~p"/town-square")}
    else
      mount_guild_hall(socket)
    end
  end

  defp mount_guild_hall(socket) do
    neurons = list_members()

    strategy_previews =
      Map.new(neurons, fn m -> {m.id, m.strategy} end)

    thoughts = ExCortex.Thoughts.list_thoughts()

    member_quests =
      Map.new(neurons, fn m ->
        matching = Enum.filter(thoughts, &member_in_quest?(m.name, &1))
        {m.name, Enum.map(matching, & &1.name)}
      end)

    banner = Settings.get_banner()
    banner_atom = if banner, do: String.to_existing_atom(banner)

    {:ok,
     assign(socket,
       neurons: neurons,
       member_quests: member_quests,
       expanded: MapSet.new(),
       custom_prefill: %{name: "", team: "", system_prompt: ""},
       ollama_models: list_ollama_models(),
       strategy_previews: strategy_previews,
       editors: filter_by_banner(Builtin.editors(), banner_atom),
       analysts: filter_by_banner(Builtin.analysts(), banner_atom),
       specialists: filter_by_banner(Builtin.specialists(), banner_atom),
       advisors: filter_by_banner(Builtin.advisors(), banner_atom),
       validators: filter_by_banner(Builtin.validators(), banner_atom),
       wildcards: filter_by_banner(Builtin.wildcards(), banner_atom),
       life_use: filter_by_banner(Builtin.life_use(), banner_atom),
       active_section: "all",
       pathways: Map.new(Clusters.list_charters(), &{&1.guild_name, &1.charter_text}),
       editing_charter: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Cluster Hall")}
  end

  defp member_in_quest?(member_name, thought) do
    Enum.any?(thought.steps || [], fn step ->
      Enum.any?(step["roster"] || [], fn r -> r["who"] == member_name end)
    end)
  end

  defp filter_by_banner(neurons, nil), do: neurons
  defp filter_by_banner(neurons, banner_atom), do: Enum.filter(neurons, &(&1.banner == banner_atom))

  defp list_ollama_models do
    case Application.get_env(:ex_cortex, :ollama_models) do
      models when is_list(models) -> models
      _ -> Enum.sort(ExCortex.OllamaCache.get_models())
    end
  end

  defp list_members do
    import Ecto.Query

    from(r in Neuron, where: r.type == "role")
    |> ExCortex.Repo.all()
    |> Enum.map(&to_unified/1)
    |> Enum.sort_by(fn m ->
      {if(m.active, do: 0, else: 1), if(m.builtin, do: 0, else: 1), m.name}
    end)
  end

  defp to_unified(db) do
    builtin = lookup_builtin(db.config["member_id"])

    %{
      id: to_string(db.id),
      name: unified_name(builtin, db),
      description: builtin && builtin.description,
      category: builtin && builtin.category,
      builtin: builtin != nil,
      active: db.status == "active",
      system_prompt: unified_system_prompt(db.config, builtin),
      rank: db.config["rank"] || "journeyman",
      model: db.config["model"] || "",
      provider: db.config["provider"] || "ollama",
      strategy: db.config["strategy"] || "cot",
      team: db.team,
      db_id: db.id
    }
  end

  defp lookup_builtin(nil), do: nil
  defp lookup_builtin(member_id), do: Builtin.get(member_id)

  defp unified_name(nil, db), do: db.name
  defp unified_name(builtin, _db), do: builtin.name

  defp unified_system_prompt(config, builtin) do
    config["system_prompt"] || (builtin && builtin.system_prompt) || ""
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 class="text-3xl font-bold tracking-tight">Cluster Hall</h1>
          <p class="text-muted-foreground mt-1.5">
            Cluster roles — each neuron runs evaluations with their own model and strategy.
          </p>
          <p class="text-sm text-muted-foreground">
            {length(@neurons)} neurons · {Enum.count(@neurons, & &1.active)} active
          </p>
        </div>
        <.button
          type="button"
          variant="outline"
          size="sm"
          phx-click="set_section"
          phx-value-section="custom"
          class="shrink-0 sm:mt-1 self-start"
        >
          + Custom Neuron
        </.button>
      </div>

      <div>
        <h2 class="text-lg font-semibold mb-1">Cluster Pathways</h2>
        <p class="text-sm text-muted-foreground mb-4">
          Shared values, domain rules, and output expectations prepended to every neuron's context during evaluation.
        </p>
        <div class="space-y-3">
          <%= for {guild_name, charter_text} <- Enum.sort(@pathways) do %>
            <div class="rounded-lg border bg-card p-4">
              <div class="flex items-center justify-between mb-2">
                <span class="font-medium text-sm">{guild_name}</span>
                <.button
                  type="button"
                  phx-click="edit_charter"
                  phx-value-cluster={guild_name}
                  variant="ghost"
                  size="sm"
                >
                  Edit
                </.button>
              </div>
              <%= if @editing_charter == guild_name do %>
                <form phx-submit="save_charter">
                  <input type="hidden" name="guild_name" value={guild_name} />
                  <textarea
                    name="charter_text"
                    class="w-full text-xs font-mono border rounded p-2 h-24"
                    placeholder="Shared values, domain rules, output expectations..."
                  ><%= charter_text %></textarea>
                  <div class="flex gap-2 mt-1">
                    <.button type="submit" size="sm">Save</.button>
                    <.button type="button" phx-click="cancel_charter" variant="ghost" size="sm">
                      Cancel
                    </.button>
                  </div>
                </form>
              <% else %>
                <%= if charter_text != "" do %>
                  <.md content={charter_text} class="prose prose-xs dark:prose-invert max-w-none" />
                <% else %>
                  <p class="text-xs text-muted-foreground italic">No pathway text set</p>
                <% end %>
              <% end %>
            </div>
          <% end %>
          <%= if @editing_charter && !Map.has_key?(@pathways, @editing_charter) do %>
            <div class="rounded-lg border bg-card p-4">
              <form phx-submit="save_charter">
                <input type="hidden" name="guild_name" value={@editing_charter} />
                <textarea
                  name="charter_text"
                  class="w-full text-xs font-mono border rounded p-2 h-24"
                  placeholder="Shared values, domain rules, output expectations..."
                ></textarea>
                <div class="flex gap-2 mt-1">
                  <.button type="submit" size="sm">Save</.button>
                  <.button type="button" phx-click="cancel_charter" variant="ghost" size="sm">
                    Cancel
                  </.button>
                </div>
              </form>
            </div>
          <% end %>
          <.button
            type="button"
            phx-click="edit_charter"
            phx-value-cluster="default"
            variant="outline"
            size="sm"
          >
            + Add Pathway
          </.button>
        </div>
      </div>

      <div class="space-y-3">
        <.member_card
          :for={neuron <- @neurons}
          neuron={neuron}
          expanded={MapSet.member?(@expanded, neuron.id)}
          ollama_models={@ollama_models}
          strategy_preview={Map.get(@strategy_previews, neuron.id, neuron.strategy)}
          member_quests={Map.get(@member_quests, neuron.name, [])}
        />
      </div>

      <div>
        <h2 class="text-lg font-semibold mb-1">Recruit a Neuron</h2>
        <p class="text-sm text-muted-foreground mb-4">
          Add a pre-configured neuron role to your cluster.
        </p>

        <div class="flex overflow-x-auto border-b mb-6">
          <%= for {section_id, label} <- catalog_tabs() do %>
            <button
              type="button"
              phx-click="set_section"
              phx-value-section={section_id}
              class={[
                "px-4 py-2 text-sm whitespace-nowrap border-b-2 -mb-px transition-colors",
                if(@active_section == section_id,
                  do: "border-foreground text-foreground font-medium",
                  else: "border-transparent text-muted-foreground hover:text-foreground"
                )
              ]}
            >
              {label}
            </button>
          <% end %>
        </div>

        <% sections = catalog_sections(assigns) %>
        <div class="min-h-[1100px]">
          <%= if @active_section == "all" do %>
            <div class="space-y-10">
              <%= for {_id, title, neurons, description} <- sections do %>
                <.member_section title={title} description={description} neurons={neurons} />
              <% end %>
            </div>
          <% else %>
            <%= if @active_section == "custom" do %>
              <.new_member_card
                ollama_models={@ollama_models}
                strategy_preview={@strategy_previews["new"] || "cod"}
                prefill={@custom_prefill}
              />
            <% else %>
              <% section = Enum.find(sections, fn {id, _, _, _} -> id == @active_section end) %>
              <%= if section do %>
                <% {_id, _title, neurons, _description} = section %>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <.member_row :for={neuron <- neurons} neuron={neuron} />
                </div>
              <% else %>
                <p class="text-muted-foreground text-sm">
                  No neurons available in this category for the current banner.
                </p>
              <% end %>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :neuron, :map, required: true
  attr :expanded, :boolean, required: true
  attr :ollama_models, :list, required: true
  attr :strategy_preview, :string, required: true
  attr :member_quests, :list, default: []

  defp member_card(assigns) do
    ~H"""
    <div class={[
      "border rounded-lg bg-card transition-opacity",
      if(!@neuron.active, do: "opacity-60")
    ]}>
      <div class="flex items-stretch">
        <div
          class="flex flex-1 items-center gap-3 cursor-pointer min-w-0 px-5 py-4"
          phx-click="toggle_expand"
          phx-value-id={@neuron.id}
        >
          <span class={["transition-transform text-muted-foreground", if(@expanded, do: "rotate-90")]}>
            ›
          </span>
          <div class="flex-1 flex items-center gap-2 min-w-0">
            <span class="font-medium truncate">{@neuron.name}</span>
            <%= if @neuron.team do %>
              <.badge variant="outline" class="text-xs shrink-0">{@neuron.team}</.badge>
            <% end %>
          </div>
          <%= if @member_quests != [] do %>
            <p class="text-xs text-muted-foreground mt-0.5">
              Used in: {Enum.join(@member_quests, ", ")}
            </p>
          <% end %>
          <.rank_pill rank={@neuron.rank} model={@neuron.model} />
        </div>
        <button
          class="relative inline-flex self-center h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50 mr-5"
          style={"background-color: #{if @neuron.active, do: "hsl(var(--primary))", else: "hsl(var(--input))"}"}
          phx-click="toggle_active"
          phx-value-id={@neuron.id}
          phx-value-active={if @neuron.active, do: "true", else: "false"}
          aria-label={
            if @neuron.active, do: "Deactivate #{@neuron.name}", else: "Activate #{@neuron.name}"
          }
          type="button"
        >
          <span
            class="pointer-events-none inline-block h-4 w-4 rounded-full bg-background shadow-lg ring-0 transition-transform"
            style={"transform: translateX(#{if @neuron.active, do: "16px", else: "0px"})"}
          >
          </span>
        </button>
      </div>

      <%= if @expanded do %>
        <div class="border-t px-5 py-5">
          <form phx-submit="save_member" phx-change="preview_strategy" class="space-y-4">
            <input type="hidden" name="neuron[id]" value={@neuron.id} />
            <input
              type="hidden"
              name="neuron[builtin]"
              value={if @neuron.builtin, do: "true", else: "false"}
            />

            <%= if !@neuron.builtin do %>
              <div>
                <label class="text-sm font-medium">Name</label>
                <.input type="text" name="neuron[name]" value={@neuron.name} />
              </div>
            <% end %>

            <div>
              <label class="text-sm font-medium">Team</label>
              <.input
                type="text"
                name="neuron[team]"
                value={@neuron.team || ""}
                placeholder="e.g. security, quality, editors"
              />
            </div>

            <div>
              <label class="text-sm font-medium">System Prompt</label>
              <.input
                type="textarea"
                name="neuron[system_prompt]"
                value={@neuron.system_prompt}
                rows={5}
              />
            </div>

            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <div>
                <label for="neuron-rank-edit" class="text-sm font-medium">Rank</label>
                <select
                  id="neuron-rank-edit"
                  name="neuron[rank]"
                  class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
                >
                  <option value="apprentice" selected={@neuron.rank == "apprentice"}>
                    Apprentice
                  </option>
                  <option value="journeyman" selected={@neuron.rank == "journeyman"}>
                    Journeyman
                  </option>
                  <option value="master" selected={@neuron.rank == "master"}>Master</option>
                </select>
              </div>
              <div>
                <label for={"neuron-provider-edit-#{@neuron.id}"} class="text-sm font-medium">
                  Provider
                </label>
                <select
                  id={"neuron-provider-edit-#{@neuron.id}"}
                  name="neuron[provider]"
                  class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
                >
                  <option value="ollama" selected={@neuron.provider == "ollama"}>
                    Ollama (local)
                  </option>
                  <option value="claude" selected={@neuron.provider == "claude"}>
                    Claude (Anthropic)
                  </option>
                </select>
              </div>
              <div>
                <label for={"neuron-model-edit-#{@neuron.id}"} class="text-sm font-medium">
                  Model
                </label>
                <select
                  id={"neuron-model-edit-#{@neuron.id}"}
                  name="neuron[model]"
                  class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
                >
                  <option value="" selected={@neuron.model == ""}>— select model —</option>
                  <option
                    :for={model <- @ollama_models}
                    value={model}
                    selected={@neuron.model == model}
                  >
                    {model}
                  </option>
                </select>
              </div>
              <div>
                <label for={"neuron-strategy-edit-#{@neuron.id}"} class="text-sm font-medium">
                  Strategy
                </label>
                <select
                  id={"neuron-strategy-edit-#{@neuron.id}"}
                  name="neuron[strategy]"
                  class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
                >
                  <option value="cot" selected={@neuron.strategy == "cot"}>cot</option>
                  <option value="cod" selected={@neuron.strategy == "cod"}>cod</option>
                  <option value="default" selected={@neuron.strategy == "default"}>default</option>
                </select>
                <p class="text-xs text-muted-foreground mt-1">
                  <%= case @strategy_preview do %>
                    <% "cot" -> %>
                      Chain of Thought — reason step by step before answering. Better accuracy, more tokens.
                    <% "cod" -> %>
                      Chain of Density — compact, high-signal reasoning. Faster, lower cost.
                    <% _ -> %>
                      Uses the model's default prompting style.
                  <% end %>
                </p>
              </div>
            </div>

            <div class="flex justify-between pt-2">
              <.button
                type="button"
                variant="destructive"
                size="sm"
                phx-click="delete_member"
                phx-value-id={@neuron.id}
                data-confirm="Delete this member?"
              >
                Delete
              </.button>
              <.button type="submit" size="sm">Save</.button>
            </div>
          </form>
        </div>
      <% end %>
    </div>
    """
  end

  attr :ollama_models, :list, required: true
  attr :strategy_preview, :string, required: true
  attr :prefill, :map, default: %{name: "", team: "", system_prompt: ""}

  defp new_member_card(assigns) do
    ~H"""
    <div class="border rounded-lg bg-card border-dashed">
      <div class="px-4 py-4">
        <form phx-submit="create_member" phx-change="preview_strategy_new" class="space-y-4">
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div>
              <label class="text-sm font-medium">Name</label>
              <.input
                type="text"
                name="neuron[name]"
                value={@prefill[:name]}
                placeholder="e.g. safety-reviewer"
              />
            </div>
            <div>
              <label class="text-sm font-medium">Team</label>
              <.input
                type="text"
                name="neuron[team]"
                value={@prefill[:team]}
                placeholder="e.g. security"
              />
            </div>
          </div>
          <div>
            <label class="text-sm font-medium">System Prompt</label>
            <.input
              type="textarea"
              name="neuron[system_prompt]"
              value={@prefill[:system_prompt]}
              rows={4}
              placeholder="You are a..."
            />
          </div>
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <div>
              <label for="neuron-rank-new" class="text-sm font-medium">Rank</label>
              <select
                id="neuron-rank-new"
                name="neuron[rank]"
                class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
              >
                <option value="apprentice">Apprentice</option>
                <option value="journeyman" selected>Journeyman</option>
                <option value="master">Master</option>
              </select>
            </div>
            <div>
              <label for="neuron-provider-new" class="text-sm font-medium">Provider</label>
              <select
                id="neuron-provider-new"
                name="neuron[provider]"
                class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
              >
                <option value="ollama" selected>Ollama (local)</option>
                <option value="claude">Claude (Anthropic)</option>
              </select>
            </div>
            <div>
              <label for="neuron-model-new" class="text-sm font-medium">Model</label>
              <select
                id="neuron-model-new"
                name="neuron[model]"
                class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
              >
                <option value="">— select model —</option>
                <option :for={model <- @ollama_models} value={model}>{model}</option>
              </select>
            </div>
            <div>
              <label for="neuron-strategy-new" class="text-sm font-medium">Strategy</label>
              <select
                id="neuron-strategy-new"
                name="neuron[strategy]"
                class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
              >
                <option value="cot">cot</option>
                <option value="cod" selected>cod</option>
                <option value="default">default</option>
              </select>
              <p class="text-xs text-muted-foreground mt-1">
                <%= case @strategy_preview do %>
                  <% "cot" -> %>
                    Chain of Thought — reason step by step before answering. Better accuracy, more tokens.
                  <% "cod" -> %>
                    Chain of Density — compact, high-signal reasoning. Faster, lower cost.
                  <% _ -> %>
                    Uses the model's default prompting style.
                <% end %>
              </p>
            </div>
          </div>
          <div class="flex justify-end gap-2 pt-2">
            <.button
              type="button"
              variant="outline"
              size="sm"
              phx-click="set_section"
              phx-value-section="all"
            >
              Cancel
            </.button>
            <.button type="submit" size="sm">Create Neuron</.button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  attr :rank, :string, required: true
  attr :model, :string, required: true

  defp rank_pill(assigns) do
    {color_classes, label} =
      case assigns.rank do
        "apprentice" ->
          {"border-l-2 border-amber-700 bg-amber-50 text-amber-700", "Apprentice"}

        "master" ->
          {"border-l-2 border-yellow-500 bg-yellow-50 text-yellow-600", "Master"}

        _ ->
          {"border-l-2 border-slate-400 bg-slate-100 text-slate-500", "Journeyman"}
      end

    assigns = assign(assigns, color_classes: color_classes, label: label)

    ~H"""
    <span class={["flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium", @color_classes]}>
      <span class="font-bold">{@label}</span>
      <span class="opacity-75 max-w-20 truncate">{if @model == "", do: "—", else: @model}</span>
    </span>
    """
  end

  defp catalog_tabs do
    [
      {"all", "All"},
      {"editors", "Editors"},
      {"analysts", "Analysts"},
      {"specialists", "Specialists"},
      {"advisors", "Advisors"},
      {"validators", "Validators"},
      {"wildcards", "Wildcards"},
      {"life_use", "Life Use"},
      {"custom", "Custom"}
    ]
  end

  defp catalog_sections(assigns) do
    Enum.reject(
      [
        {"editors", "Editors", assigns.editors, "Text quality and writing review"},
        {"analysts", "Analysts", assigns.analysts, "Data interpretation and pattern recognition"},
        {"specialists", "Specialists", assigns.specialists, "Domain-specific technical expertise"},
        {"advisors", "Advisors", assigns.advisors, "Perspective, judgment, and risk assessment"},
        {"validators", "Validators", assigns.validators, "Evidence standards and quality gates"},
        {"wildcards", "Wildcards", assigns.wildcards, "Creative perspectives and personality-driven evaluation"},
        {"life_use", "Life Use", assigns.life_use, "Personal productivity, news, and lifestyle"}
      ],
      fn {_, _, neurons, _} -> neurons == [] end
    )
  end

  defp member_section(assigns) do
    ~H"""
    <div>
      <h3 class="text-base font-semibold mb-1">{@title}</h3>
      <p class="text-muted-foreground text-sm mb-4">{@description}</p>
      <div class="space-y-3">
        <%= for neuron <- @neurons do %>
          <.member_row neuron={neuron} />
        <% end %>
      </div>
    </div>
    """
  end

  defp member_row(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 rounded-lg border p-5 sm:flex-row sm:items-center sm:justify-between">
      <div class="space-y-1">
        <div class="flex items-center gap-2">
          <span class="font-medium">{@neuron.name}</span>
          <.badge variant="secondary">{@neuron.category}</.badge>
        </div>
        <p class="text-sm text-muted-foreground">{@neuron.description}</p>
      </div>
      <div class="shrink-0 flex gap-2 self-start sm:self-auto">
        <.button
          type="button"
          size="sm"
          variant="outline"
          phx-click="recruit"
          phx-value-neuron-id={@neuron.id}
          phx-value-rank="apprentice"
        >
          Apprentice
        </.button>
        <.button
          type="button"
          size="sm"
          variant="outline"
          phx-click="recruit"
          phx-value-neuron-id={@neuron.id}
          phx-value-rank="journeyman"
        >
          Journeyman
        </.button>
        <.button
          type="button"
          size="sm"
          phx-click="recruit"
          phx-value-neuron-id={@neuron.id}
          phx-value-rank="master"
        >
          Master
        </.button>
        <.button
          type="button"
          size="sm"
          variant="ghost"
          phx-click="customize_builtin"
          phx-value-neuron-id={@neuron.id}
        >
          Add Custom
        </.button>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("recruit", %{"neuron-id" => member_id, "rank" => rank}, socket) do
    neuron = Builtin.get(member_id)
    rank_atom = String.to_existing_atom(rank)
    rank_config = neuron.ranks[rank_atom]

    attrs = %{
      type: "role",
      name: neuron.name,
      status: "active",
      source: "db",
      team: to_string(neuron.category),
      config: %{
        "member_id" => member_id,
        "system_prompt" => neuron.system_prompt,
        "rank" => rank,
        "model" => rank_config.model,
        "strategy" => rank_config.strategy
      }
    }

    %Neuron{}
    |> Neuron.changeset(attrs)
    |> ExCortex.Repo.insert(on_conflict: :nothing)

    {:noreply,
     socket
     |> put_flash(:info, "#{neuron.name} (#{rank}) recruited!")
     |> assign(neurons: list_members())}
  end

  @impl true
  def handle_event("toggle_expand", %{"id" => id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded, id),
        do: MapSet.delete(socket.assigns.expanded, id),
        else: MapSet.put(socket.assigns.expanded, id)

    {:noreply, assign(socket, expanded: expanded)}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id, "active" => current_active}, socket) do
    new_status = if current_active == "true", do: "draft", else: "active"

    case ExCortex.Repo.get(Neuron, id) do
      nil -> :ok
      db -> db |> Neuron.changeset(%{status: new_status}) |> ExCortex.Repo.update()
    end

    {:noreply, assign(socket, neurons: list_members())}
  end

  @impl true
  def handle_event("preview_strategy", %{"neuron" => %{"id" => id, "strategy" => strategy}}, socket) do
    previews = Map.put(socket.assigns.strategy_previews, id, strategy)
    {:noreply, assign(socket, strategy_previews: previews)}
  end

  def handle_event("preview_strategy", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("preview_strategy_new", %{"neuron" => %{"strategy" => strategy}}, socket) do
    previews = Map.put(socket.assigns.strategy_previews, "new", strategy)
    {:noreply, assign(socket, strategy_previews: previews)}
  end

  def handle_event("preview_strategy_new", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("add_new", _params, socket) do
    {:noreply, assign(socket, active_section: "custom")}
  end

  @impl true
  def handle_event("cancel_new", _params, socket) do
    {:noreply, assign(socket, active_section: "all", custom_prefill: %{name: "", team: "", system_prompt: ""})}
  end

  @impl true
  def handle_event("customize_builtin", %{"neuron-id" => member_id}, socket) do
    neuron = Builtin.get(member_id)

    prefill = %{
      name: neuron.name,
      team: to_string(neuron.category),
      system_prompt: neuron.system_prompt
    }

    {:noreply, assign(socket, active_section: "custom", custom_prefill: prefill)}
  end

  @impl true
  def handle_event("create_member", %{"neuron" => params}, socket) do
    team = blank_to_nil(params["team"])

    attrs = %{
      type: "role",
      name: params["name"],
      source: "db",
      status: "active",
      team: team,
      config: %{
        "system_prompt" => params["system_prompt"] || "",
        "rank" => params["rank"] || "journeyman",
        "model" => params["model"] || "",
        "provider" => params["provider"] || "ollama",
        "strategy" => params["strategy"] || "cot"
      }
    }

    case %Neuron{} |> Neuron.changeset(attrs) |> ExCortex.Repo.insert() do
      {:ok, _} ->
        neurons = list_members()
        previews = Map.new(neurons, fn m -> {m.id, m.strategy} end)

        {:noreply,
         assign(socket,
           neurons: neurons,
           active_section: "all",
           custom_prefill: %{name: "", team: "", system_prompt: ""},
           strategy_previews: previews
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create neuron")}
    end
  end

  @impl true
  def handle_event("save_member", %{"neuron" => params}, socket) do
    id = params["id"]
    builtin = params["builtin"] == "true"

    case ExCortex.Repo.get(Neuron, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Neuron not found")}

      db ->
        case update_member_from_params(db, params, builtin) do
          {:ok, _} -> {:noreply, assign(socket, neurons: list_members())}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to save neuron")}
        end
    end
  end

  @impl true
  def handle_event("delete_member", %{"id" => id}, socket) do
    case ExCortex.Repo.get(Neuron, id) do
      nil ->
        {:noreply, socket}

      db ->
        ExCortex.Repo.delete(db)
        {:noreply, assign(socket, neurons: list_members())}
    end
  end

  @impl true
  def handle_event("set_section", %{"section" => section}, socket) do
    {:noreply, assign(socket, active_section: section)}
  end

  @impl true
  def handle_event("edit_charter", %{"cluster" => guild_name}, socket) do
    {:noreply, assign(socket, editing_charter: guild_name)}
  end

  @impl true
  def handle_event("save_charter", %{"guild_name" => guild_name, "charter_text" => text}, socket) do
    {:ok, _} = Clusters.upsert_charter(guild_name, text)
    pathways = Map.new(Clusters.list_charters(), &{&1.guild_name, &1.charter_text})
    {:noreply, assign(socket, pathways: pathways, editing_charter: nil)}
  end

  @impl true
  def handle_event("cancel_charter", _, socket) do
    {:noreply, assign(socket, editing_charter: nil)}
  end

  defp update_member_from_params(db, params, builtin) do
    config =
      Map.merge(db.config || %{}, %{
        "system_prompt" => params["system_prompt"] || "",
        "rank" => params["rank"] || "journeyman",
        "model" => params["model"] || "",
        "provider" => params["provider"] || "ollama",
        "strategy" => params["strategy"] || "cot"
      })

    team = blank_to_nil(params["team"])

    attrs =
      if builtin,
        do: %{config: config, team: team},
        else: %{name: params["name"] || db.name, config: config, team: team}

    db |> Neuron.changeset(attrs) |> ExCortex.Repo.update()
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
