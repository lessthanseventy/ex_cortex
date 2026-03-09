defmodule ExCaliburWeb.MembersLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge
  import SaladUI.Button

  alias Excellence.Schemas.Member
  alias ExCalibur.Members.BuiltinMember

  @impl true
  def mount(_params, _session, socket) do
    members = list_members()

    strategy_previews =
      Map.new(members, fn m -> {m.id, m.strategy} end)

    {:ok,
     assign(socket,
       members: members,
       expanded: MapSet.new(),
       adding_new: false,
       ollama_models: list_ollama_models(),
       strategy_previews: strategy_previews
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Members")}
  end

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
          <h1 class="text-3xl font-bold tracking-tight">Members</h1>
          <p class="text-muted-foreground mt-1.5">
            Guild roles — each member runs evaluations with their own model and strategy.
          </p>
        </div>
        <.button variant="outline" size="sm" phx-click="add_new" class="shrink-0 sm:mt-1 self-start">
          + New Member
        </.button>
      </div>

      <%= if @adding_new do %>
        <.new_member_card ollama_models={@ollama_models} strategy_preview={@strategy_previews["new"] || "cod"} />
      <% end %>

      <div class="space-y-3">
        <.member_card
          :for={member <- @members}
          member={member}
          expanded={MapSet.member?(@expanded, member.id)}
          ollama_models={@ollama_models}
          strategy_preview={Map.get(@strategy_previews, member.id, member.strategy)}
        />
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
          aria-label={if @member.active, do: "Deactivate #{@member.name}", else: "Activate #{@member.name}"}
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

            <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
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

  defp new_member_card(assigns) do
    ~H"""
    <div class="border rounded-lg bg-card border-dashed">
      <div class="px-4 py-4">
        <form phx-submit="create_member" phx-change="preview_strategy_new" class="space-y-4">
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div>
              <label class="text-sm font-medium">Name</label>
              <.input type="text" name="member[name]" value="" placeholder="e.g. safety-reviewer" />
            </div>
            <div>
              <label class="text-sm font-medium">Team</label>
              <.input type="text" name="member[team]" value="" placeholder="e.g. security" />
            </div>
          </div>
          <div>
            <label class="text-sm font-medium">System Prompt</label>
            <.input
              type="textarea"
              name="member[system_prompt]"
              value=""
              rows={4}
              placeholder="You are a..."
            />
          </div>
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
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
            <.button type="button" variant="outline" size="sm" phx-click="cancel_new">
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
    {:noreply, assign(socket, adding_new: true)}
  end

  @impl true
  def handle_event("cancel_new", _params, socket) do
    {:noreply, assign(socket, adding_new: false)}
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
        "strategy" => params["strategy"] || "cot"
      }
    }

    case %Member{} |> Member.changeset(attrs) |> ExCalibur.Repo.insert() do
      {:ok, _} ->
        members = list_members()
        previews = Map.new(members, fn m -> {m.id, m.strategy} end)
        {:noreply, assign(socket, members: members, adding_new: false, strategy_previews: previews)}

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
end
