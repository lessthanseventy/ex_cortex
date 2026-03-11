defmodule ExCaliburWeb.GuildHallLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge
  import SaladUI.Button

  alias ExCalibur.GuildCharters
  alias ExCalibur.Members.BuiltinMember
  alias ExCalibur.Settings
  alias Excellence.Schemas.Member

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) and is_nil(Settings.get_banner()) do
      {:ok, push_navigate(socket, to: ~p"/town-square")}
    else
      mount_guild_hall(socket)
    end
  end

  defp mount_guild_hall(socket) do
    members = list_members()

    strategy_previews =
      Map.new(members, fn m -> {m.id, m.strategy} end)

    banner = Settings.get_banner()
    banner_atom = if banner, do: String.to_existing_atom(banner)

    {:ok,
     assign(socket,
       members: members,
       expanded: MapSet.new(),
       custom_prefill: %{name: "", team: "", system_prompt: ""},
       ollama_models: list_ollama_models(),
       strategy_previews: strategy_previews,
       editors: filter_by_banner(BuiltinMember.editors(), banner_atom),
       analysts: filter_by_banner(BuiltinMember.analysts(), banner_atom),
       specialists: filter_by_banner(BuiltinMember.specialists(), banner_atom),
       advisors: filter_by_banner(BuiltinMember.advisors(), banner_atom),
       validators: filter_by_banner(BuiltinMember.validators(), banner_atom),
       wildcards: filter_by_banner(BuiltinMember.wildcards(), banner_atom),
       active_section: "all",
       charters: Map.new(GuildCharters.list_charters(), &{&1.guild_name, &1.charter_text}),
       editing_charter: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Guild Hall")}
  end

  defp filter_by_banner(members, nil), do: members
  defp filter_by_banner(members, banner_atom), do: Enum.filter(members, &(&1.banner == banner_atom))

  defp list_ollama_models do
    url = Application.get_env(:ex_calibur, :ollama_url, "http://127.0.0.1:11434")

    case Req.get("#{url}/api/tags") do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        models |> Enum.map(& &1["name"]) |> Enum.sort()

      _ ->
        []
    end
  end

  defp list_members do
    import Ecto.Query

    from(r in Member, where: r.type == "role")
    |> ExCalibur.Repo.all()
    |> Enum.map(&to_unified/1)
    |> Enum.sort_by(fn m ->
      {if(m.active, do: 0, else: 1), if(m.builtin, do: 0, else: 1), m.name}
    end)
  end

  defp to_unified(db) do
    builtin =
      case db.config["member_id"] do
        nil -> nil
        member_id -> BuiltinMember.get(member_id)
      end

    %{
      id: to_string(db.id),
      name: if(builtin, do: builtin.name, else: db.name),
      description: builtin && builtin.description,
      category: builtin && builtin.category,
      builtin: builtin != nil,
      active: db.status == "active",
      system_prompt: db.config["system_prompt"] || (builtin && builtin.system_prompt) || "",
      rank: db.config["rank"] || "journeyman",
      model: db.config["model"] || "",
      provider: db.config["provider"] || "ollama",
      strategy: db.config["strategy"] || "cot",
      team: db.team,
      db_id: db.id
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 class="text-3xl font-bold tracking-tight">Guild Hall</h1>
          <p class="text-muted-foreground mt-1.5">
            Guild roles — each member runs evaluations with their own model and strategy.
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
          + Custom Member
        </.button>
      </div>

      <div>
        <h2 class="text-lg font-semibold mb-1">Guild Charters</h2>
        <p class="text-sm text-muted-foreground mb-4">
          Shared values, domain rules, and output expectations prepended to every member's context during evaluation.
        </p>
        <div class="space-y-3">
          <%= for {guild_name, charter_text} <- Enum.sort(@charters) do %>
            <div class="rounded-lg border bg-card p-4">
              <div class="flex items-center justify-between mb-2">
                <span class="font-medium text-sm">{guild_name}</span>
                <.button
                  type="button"
                  phx-click="edit_charter"
                  phx-value-guild={guild_name}
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
                  <p class="text-xs text-muted-foreground italic">No charter text set</p>
                <% end %>
              <% end %>
            </div>
          <% end %>
          <%= if @editing_charter && !Map.has_key?(@charters, @editing_charter) do %>
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
            phx-value-guild="default"
            variant="outline"
            size="sm"
          >
            + Add Charter
          </.button>
        </div>
      </div>

      <div class="space-y-3">
        <.member_card
          :for={member <- @members}
          member={member}
          expanded={MapSet.member?(@expanded, member.id)}
          ollama_models={@ollama_models}
          strategy_preview={Map.get(@strategy_previews, member.id, member.strategy)}
        />
      </div>

      <div>
        <h2 class="text-lg font-semibold mb-1">Recruit a Member</h2>
        <p class="text-sm text-muted-foreground mb-4">
          Add a pre-configured member role to your guild.
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
              <%= for {_id, title, members, description} <- sections do %>
                <.member_section title={title} description={description} members={members} />
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
              <% {_id, _title, members, _description} =
                Enum.find(sections, fn {id, _, _, _} -> id == @active_section end) %>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <.member_row :for={member <- members} member={member} />
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :member, :map, required: true
  attr :expanded, :boolean, required: true
  attr :ollama_models, :list, required: true
  attr :strategy_preview, :string, required: true

  defp member_card(assigns) do
    ~H"""
    <div class={[
      "border rounded-lg bg-card transition-opacity",
      if(!@member.active, do: "opacity-60")
    ]}>
      <div class="flex items-stretch">
        <div
          class="flex flex-1 items-center gap-3 cursor-pointer min-w-0 px-5 py-4"
          phx-click="toggle_expand"
          phx-value-id={@member.id}
        >
          <span class={["transition-transform text-muted-foreground", if(@expanded, do: "rotate-90")]}>
            ›
          </span>
          <div class="flex-1 flex items-center gap-2 min-w-0">
            <span class="font-medium truncate">{@member.name}</span>
            <%= if @member.team do %>
              <.badge variant="outline" class="text-xs shrink-0">{@member.team}</.badge>
            <% end %>
          </div>
          <.rank_pill rank={@member.rank} model={@member.model} />
        </div>
        <button
          class="relative inline-flex self-center h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50 mr-5"
          style={"background-color: #{if @member.active, do: "hsl(var(--primary))", else: "hsl(var(--input))"}"}
          phx-click="toggle_active"
          phx-value-id={@member.id}
          phx-value-active={if @member.active, do: "true", else: "false"}
          aria-label={
            if @member.active, do: "Deactivate #{@member.name}", else: "Activate #{@member.name}"
          }
          type="button"
        >
          <span
            class="pointer-events-none inline-block h-4 w-4 rounded-full bg-background shadow-lg ring-0 transition-transform"
            style={"transform: translateX(#{if @member.active, do: "16px", else: "0px"})"}
          >
          </span>
        </button>
      </div>

      <%= if @expanded do %>
        <div class="border-t px-5 py-5">
          <form phx-submit="save_member" phx-change="preview_strategy" class="space-y-4">
            <input type="hidden" name="member[id]" value={@member.id} />
            <input
              type="hidden"
              name="member[builtin]"
              value={if @member.builtin, do: "true", else: "false"}
            />

            <%= if !@member.builtin do %>
              <div>
                <label class="text-sm font-medium">Name</label>
                <.input type="text" name="member[name]" value={@member.name} />
              </div>
            <% end %>

            <div>
              <label class="text-sm font-medium">Team</label>
              <.input
                type="text"
                name="member[team]"
                value={@member.team || ""}
                placeholder="e.g. security, quality, editors"
              />
            </div>

            <div>
              <label class="text-sm font-medium">System Prompt</label>
              <.input
                type="textarea"
                name="member[system_prompt]"
                value={@member.system_prompt}
                rows={5}
              />
            </div>

            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <div>
                <label for="member-rank-edit" class="text-sm font-medium">Rank</label>
                <select
                  id="member-rank-edit"
                  name="member[rank]"
                  class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
                >
                  <option value="apprentice" selected={@member.rank == "apprentice"}>
                    Apprentice
                  </option>
                  <option value="journeyman" selected={@member.rank == "journeyman"}>
                    Journeyman
                  </option>
                  <option value="master" selected={@member.rank == "master"}>Master</option>
                </select>
              </div>
              <div>
                <label for={"member-provider-edit-#{@member.id}"} class="text-sm font-medium">
                  Provider
                </label>
                <select
                  id={"member-provider-edit-#{@member.id}"}
                  name="member[provider]"
                  class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
                >
                  <option value="ollama" selected={@member.provider == "ollama"}>
                    Ollama (local)
                  </option>
                  <option value="claude" selected={@member.provider == "claude"}>
                    Claude (Anthropic)
                  </option>
                </select>
              </div>
              <div>
                <label for={"member-model-edit-#{@member.id}"} class="text-sm font-medium">
                  Model
                </label>
                <select
                  id={"member-model-edit-#{@member.id}"}
                  name="member[model]"
                  class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
                >
                  <option value="" selected={@member.model == ""}>— select model —</option>
                  <option
                    :for={model <- @ollama_models}
                    value={model}
                    selected={@member.model == model}
                  >
                    {model}
                  </option>
                </select>
              </div>
              <div>
                <label for={"member-strategy-edit-#{@member.id}"} class="text-sm font-medium">
                  Strategy
                </label>
                <select
                  id={"member-strategy-edit-#{@member.id}"}
                  name="member[strategy]"
                  class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
                >
                  <option value="cot" selected={@member.strategy == "cot"}>cot</option>
                  <option value="cod" selected={@member.strategy == "cod"}>cod</option>
                  <option value="default" selected={@member.strategy == "default"}>default</option>
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
                phx-value-id={@member.id}
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
                name="member[name]"
                value={@prefill[:name]}
                placeholder="e.g. safety-reviewer"
              />
            </div>
            <div>
              <label class="text-sm font-medium">Team</label>
              <.input
                type="text"
                name="member[team]"
                value={@prefill[:team]}
                placeholder="e.g. security"
              />
            </div>
          </div>
          <div>
            <label class="text-sm font-medium">System Prompt</label>
            <.input
              type="textarea"
              name="member[system_prompt]"
              value={@prefill[:system_prompt]}
              rows={4}
              placeholder="You are a..."
            />
          </div>
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <div>
              <label for="member-rank-new" class="text-sm font-medium">Rank</label>
              <select
                id="member-rank-new"
                name="member[rank]"
                class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
              >
                <option value="apprentice">Apprentice</option>
                <option value="journeyman" selected>Journeyman</option>
                <option value="master">Master</option>
              </select>
            </div>
            <div>
              <label for="member-provider-new" class="text-sm font-medium">Provider</label>
              <select
                id="member-provider-new"
                name="member[provider]"
                class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
              >
                <option value="ollama" selected>Ollama (local)</option>
                <option value="claude">Claude (Anthropic)</option>
              </select>
            </div>
            <div>
              <label for="member-model-new" class="text-sm font-medium">Model</label>
              <select
                id="member-model-new"
                name="member[model]"
                class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
              >
                <option value="">— select model —</option>
                <option :for={model <- @ollama_models} value={model}>{model}</option>
              </select>
            </div>
            <div>
              <label for="member-strategy-new" class="text-sm font-medium">Strategy</label>
              <select
                id="member-strategy-new"
                name="member[strategy]"
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
            <.button type="submit" size="sm">Create Member</.button>
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
      {"custom", "Custom"}
    ]
  end

  defp catalog_sections(assigns) do
    [
      {"editors", "Editors", assigns.editors, "Text quality and writing review"},
      {"analysts", "Analysts", assigns.analysts, "Data interpretation and pattern recognition"},
      {"specialists", "Specialists", assigns.specialists, "Domain-specific technical expertise"},
      {"advisors", "Advisors", assigns.advisors, "Perspective, judgment, and risk assessment"},
      {"validators", "Validators", assigns.validators, "Evidence standards and quality gates"},
      {"wildcards", "Wildcards", assigns.wildcards, "Creative perspectives and personality-driven evaluation"}
    ]
  end

  defp member_section(assigns) do
    ~H"""
    <div>
      <h3 class="text-base font-semibold mb-1">{@title}</h3>
      <p class="text-muted-foreground text-sm mb-4">{@description}</p>
      <div class="space-y-3">
        <%= for member <- @members do %>
          <.member_row member={member} />
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
          <span class="font-medium">{@member.name}</span>
          <.badge variant="secondary">{@member.category}</.badge>
        </div>
        <p class="text-sm text-muted-foreground">{@member.description}</p>
      </div>
      <div class="shrink-0 flex gap-2 self-start sm:self-auto">
        <.button
          type="button"
          size="sm"
          variant="outline"
          phx-click="recruit"
          phx-value-member-id={@member.id}
          phx-value-rank="apprentice"
        >
          Apprentice
        </.button>
        <.button
          type="button"
          size="sm"
          variant="outline"
          phx-click="recruit"
          phx-value-member-id={@member.id}
          phx-value-rank="journeyman"
        >
          Journeyman
        </.button>
        <.button
          type="button"
          size="sm"
          phx-click="recruit"
          phx-value-member-id={@member.id}
          phx-value-rank="master"
        >
          Master
        </.button>
        <.button
          type="button"
          size="sm"
          variant="ghost"
          phx-click="customize_builtin"
          phx-value-member-id={@member.id}
        >
          Add Custom
        </.button>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("recruit", %{"member-id" => member_id, "rank" => rank}, socket) do
    member = BuiltinMember.get(member_id)
    rank_atom = String.to_existing_atom(rank)
    rank_config = member.ranks[rank_atom]

    attrs = %{
      type: "role",
      name: member.name,
      status: "active",
      source: "db",
      team: to_string(member.category),
      config: %{
        "member_id" => member_id,
        "system_prompt" => member.system_prompt,
        "rank" => rank,
        "model" => rank_config.model,
        "strategy" => rank_config.strategy
      }
    }

    %Member{}
    |> Member.changeset(attrs)
    |> ExCalibur.Repo.insert(on_conflict: :nothing)

    {:noreply,
     socket
     |> put_flash(:info, "#{member.name} (#{rank}) recruited!")
     |> assign(members: list_members())}
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

    case ExCalibur.Repo.get(Member, id) do
      nil -> :ok
      db -> db |> Member.changeset(%{status: new_status}) |> ExCalibur.Repo.update()
    end

    {:noreply, assign(socket, members: list_members())}
  end

  @impl true
  def handle_event("preview_strategy", %{"member" => %{"id" => id, "strategy" => strategy}}, socket) do
    previews = Map.put(socket.assigns.strategy_previews, id, strategy)
    {:noreply, assign(socket, strategy_previews: previews)}
  end

  def handle_event("preview_strategy", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("preview_strategy_new", %{"member" => %{"strategy" => strategy}}, socket) do
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
  def handle_event("customize_builtin", %{"member-id" => member_id}, socket) do
    member = BuiltinMember.get(member_id)

    prefill = %{
      name: member.name,
      team: to_string(member.category),
      system_prompt: member.system_prompt
    }

    {:noreply, assign(socket, active_section: "custom", custom_prefill: prefill)}
  end

  @impl true
  def handle_event("create_member", %{"member" => params}, socket) do
    team =
      case params["team"] do
        "" -> nil
        t -> t
      end

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

    case %Member{} |> Member.changeset(attrs) |> ExCalibur.Repo.insert() do
      {:ok, _} ->
        members = list_members()
        previews = Map.new(members, fn m -> {m.id, m.strategy} end)

        {:noreply,
         assign(socket,
           members: members,
           active_section: "all",
           custom_prefill: %{name: "", team: "", system_prompt: ""},
           strategy_previews: previews
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create member")}
    end
  end

  @impl true
  def handle_event("save_member", %{"member" => params}, socket) do
    id = params["id"]
    builtin = params["builtin"] == "true"

    case ExCalibur.Repo.get(Member, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Member not found")}

      db ->
        config =
          Map.merge(db.config || %{}, %{
            "system_prompt" => params["system_prompt"] || "",
            "rank" => params["rank"] || "journeyman",
            "model" => params["model"] || "",
            "provider" => params["provider"] || "ollama",
            "strategy" => params["strategy"] || "cot"
          })

        team =
          case params["team"] do
            "" -> nil
            t -> t
          end

        attrs =
          if builtin,
            do: %{config: config, team: team},
            else: %{name: params["name"] || db.name, config: config, team: team}

        case db |> Member.changeset(attrs) |> ExCalibur.Repo.update() do
          {:ok, _} -> {:noreply, assign(socket, members: list_members())}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to save member")}
        end
    end
  end

  @impl true
  def handle_event("delete_member", %{"id" => id}, socket) do
    case ExCalibur.Repo.get(Member, id) do
      nil ->
        {:noreply, socket}

      db ->
        ExCalibur.Repo.delete(db)
        {:noreply, assign(socket, members: list_members())}
    end
  end

  @impl true
  def handle_event("set_section", %{"section" => section}, socket) do
    {:noreply, assign(socket, active_section: section)}
  end

  @impl true
  def handle_event("edit_charter", %{"guild" => guild_name}, socket) do
    {:noreply, assign(socket, editing_charter: guild_name)}
  end

  @impl true
  def handle_event("save_charter", %{"guild_name" => guild_name, "charter_text" => text}, socket) do
    {:ok, _} = GuildCharters.upsert_charter(guild_name, text)
    charters = Map.new(GuildCharters.list_charters(), &{&1.guild_name, &1.charter_text})
    {:noreply, assign(socket, charters: charters, editing_charter: nil)}
  end

  @impl true
  def handle_event("cancel_charter", _, socket) do
    {:noreply, assign(socket, editing_charter: nil)}
  end
end
