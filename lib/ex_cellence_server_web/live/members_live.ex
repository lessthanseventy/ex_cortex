defmodule ExCellenceServerWeb.MembersLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import SaladUI.Badge
  import SaladUI.Button

  alias Excellence.Schemas.Member
  alias ExCellenceServer.Members.BuiltinMember

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, members: list_members(), expanded: MapSet.new(), adding_new: false)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Members")}
  end

  defp list_members do
    import Ecto.Query

    from(r in Member, where: r.type == "role")
    |> ExCellenceServer.Repo.all()
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
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Members</h1>
        <.button variant="outline" size="sm" phx-click="add_new">+ New Member</.button>
      </div>

      <%= if @adding_new do %>
        <.new_member_card />
      <% end %>

      <div class="space-y-2">
        <.member_card
          :for={member <- @members}
          member={member}
          expanded={MapSet.member?(@expanded, member.id)}
        />
      </div>
    </div>
    """
  end

  attr :member, :map, required: true
  attr :expanded, :boolean, required: true

  defp member_card(assigns) do
    ~H"""
    <div class={[
      "border rounded-lg bg-card transition-opacity",
      if(!@member.active, do: "opacity-60")
    ]}>
      <div class="flex items-center gap-3 px-4 py-3">
        <div
          class="flex flex-1 items-center gap-3 cursor-pointer min-w-0"
          phx-click="toggle_expand"
          phx-value-id={@member.id}
        >
          <span class={["transition-transform text-muted-foreground", if(@expanded, do: "rotate-90")]}>
            ›
          </span>
          <div class="flex-1 flex items-center gap-2 min-w-0">
            <span class="font-medium truncate">{@member.name}</span>
            <%= if @member.category do %>
              <.badge variant="outline" class="text-xs shrink-0">{@member.category}</.badge>
            <% end %>
          </div>
          <.rank_pill rank={@member.rank} model={@member.model} />
        </div>
        <button
          class="relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50"
          style={"background-color: #{if @member.active, do: "hsl(var(--primary))", else: "hsl(var(--input))"}"}
          phx-click="toggle_active"
          phx-value-id={@member.id}
          phx-value-active={if @member.active, do: "true", else: "false"}
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
        <div class="border-t px-4 py-4">
          <form phx-submit="save_member" class="space-y-4">
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
              <label class="text-sm font-medium">System Prompt</label>
              <.input
                type="textarea"
                name="member[system_prompt]"
                value={@member.system_prompt}
                rows={5}
              />
            </div>

            <div class="grid grid-cols-3 gap-3">
              <div>
                <label class="text-sm font-medium">Rank</label>
                <select
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
                <label class="text-sm font-medium">Model</label>
                <.input
                  type="text"
                  name="member[model]"
                  value={@member.model}
                  placeholder="e.g. gemma3:4b"
                />
              </div>
              <div>
                <label class="text-sm font-medium">Strategy</label>
                <select
                  name="member[strategy]"
                  class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
                >
                  <option value="cot" selected={@member.strategy == "cot"}>cot</option>
                  <option value="cod" selected={@member.strategy == "cod"}>cod</option>
                  <option value="default" selected={@member.strategy == "default"}>default</option>
                </select>
                <p class="text-xs text-muted-foreground mt-1">
                  <%= case @member.strategy do %>
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

  defp new_member_card(assigns) do
    ~H"""
    <div class="border rounded-lg bg-card border-dashed">
      <div class="px-4 py-4">
        <form phx-submit="create_member" class="space-y-4">
          <div>
            <label class="text-sm font-medium">Name</label>
            <.input type="text" name="member[name]" value="" placeholder="e.g. safety-reviewer" />
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
          <div class="grid grid-cols-3 gap-3">
            <div>
              <label class="text-sm font-medium">Rank</label>
              <select
                name="member[rank]"
                class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
              >
                <option value="apprentice">Apprentice</option>
                <option value="journeyman" selected>Journeyman</option>
                <option value="master">Master</option>
              </select>
            </div>
            <div>
              <label class="text-sm font-medium">Model</label>
              <.input type="text" name="member[model]" value="" placeholder="e.g. gemma3:4b" />
            </div>
            <div>
              <label class="text-sm font-medium">Strategy</label>
              <select
                name="member[strategy]"
                class="w-full text-sm border rounded px-2 py-1 bg-background mt-1"
              >
                <option value="cot">cot — step by step reasoning</option>
                <option value="cod" selected>cod — compact, high-signal</option>
                <option value="default">default — model default</option>
              </select>
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

    case ExCellenceServer.Repo.get(Member, id) do
      nil -> :ok
      db -> db |> Member.changeset(%{status: new_status}) |> ExCellenceServer.Repo.update()
    end

    {:noreply, assign(socket, members: list_members())}
  end

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
    attrs = %{
      type: "role",
      name: params["name"],
      source: "db",
      status: "active",
      config: %{
        "system_prompt" => params["system_prompt"] || "",
        "rank" => params["rank"] || "journeyman",
        "model" => params["model"] || "",
        "strategy" => params["strategy"] || "cot"
      }
    }

    case %Member{} |> Member.changeset(attrs) |> ExCellenceServer.Repo.insert() do
      {:ok, _} -> {:noreply, assign(socket, members: list_members(), adding_new: false)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to create member")}
    end
  end

  @impl true
  def handle_event("save_member", %{"member" => params}, socket) do
    id = params["id"]
    builtin = params["builtin"] == "true"

    case ExCellenceServer.Repo.get(Member, id) do
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

        attrs =
          if builtin,
            do: %{config: config},
            else: %{name: params["name"] || db.name, config: config}

        case db |> Member.changeset(attrs) |> ExCellenceServer.Repo.update() do
          {:ok, _} -> {:noreply, assign(socket, members: list_members())}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to save member")}
        end
    end
  end

  @impl true
  def handle_event("delete_member", %{"id" => id}, socket) do
    case ExCellenceServer.Repo.get(Member, id) do
      nil ->
        {:noreply, socket}

      db ->
        ExCellenceServer.Repo.delete(db)
        {:noreply, assign(socket, members: list_members())}
    end
  end
end
