defmodule ExCellenceServerWeb.MembersLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import SaladUI.Badge
  import SaladUI.Button

  alias Excellence.Schemas.ResourceDefinition
  alias ExCellenceServer.Members.Member

  @impl true
  def mount(_params, _session, socket) do
    members = list_members()
    {:ok, assign(socket, members: members, expanded: MapSet.new(), adding_new: false)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Members")}
  end

  defp list_members do
    import Ecto.Query

    db_roles =
      ExCellenceServer.Repo.all(from(r in ResourceDefinition, where: r.type == "role"))

    db_by_member_id =
      db_roles
      |> Enum.filter(&(&1.config["member_id"] != nil))
      |> Map.new(&{&1.config["member_id"], &1})

    db_custom =
      Enum.filter(db_roles, &(&1.config["member_id"] == nil))

    builtins =
      Enum.map(Member.all(), fn m ->
        db = Map.get(db_by_member_id, m.id)
        to_unified(m, db)
      end)

    customs =
      Enum.map(db_custom, &to_unified_custom/1)

    Enum.sort_by(builtins ++ customs, fn m -> {if(m.active, do: 0, else: 1), if(m.builtin, do: 0, else: 1), m.name} end)
  end

  defp to_unified(%Member{} = m, nil) do
    %{
      id: m.id,
      name: m.name,
      description: m.description,
      category: m.category,
      builtin: true,
      active: false,
      system_prompt: m.system_prompt,
      ranks: %{
        apprentice: m.ranks[:apprentice] || %{model: "", strategy: "cot"},
        journeyman: m.ranks[:journeyman] || %{model: "", strategy: "cod"},
        master: m.ranks[:master] || %{model: "", strategy: "cod"}
      },
      db_id: nil
    }
  end

  defp to_unified(%Member{} = m, db) do
    %{
      id: m.id,
      name: m.name,
      description: m.description,
      category: m.category,
      builtin: true,
      active: db.status == "active",
      system_prompt: db.config["system_prompt"] || m.system_prompt,
      ranks: %{
        apprentice: parse_rank(db.config["ranks"]["apprentice"], m.ranks[:apprentice]),
        journeyman: parse_rank(db.config["ranks"]["journeyman"], m.ranks[:journeyman]),
        master: parse_rank(db.config["ranks"]["master"], m.ranks[:master])
      },
      db_id: db.id
    }
  end

  defp to_unified_custom(db) do
    %{
      id: db.id,
      name: db.name,
      description: nil,
      category: nil,
      builtin: false,
      active: db.status == "active",
      system_prompt: db.config["system_prompt"] || "",
      ranks: %{
        apprentice: parse_rank(db.config["ranks"]["apprentice"], %{model: "", strategy: "cot"}),
        journeyman: parse_rank(db.config["ranks"]["journeyman"], %{model: "", strategy: "cod"}),
        master: parse_rank(db.config["ranks"]["master"], %{model: "", strategy: "cod"})
      },
      db_id: db.id
    }
  end

  defp parse_rank(nil, default), do: default
  defp parse_rank(r, _default), do: %{model: r["model"] || "", strategy: r["strategy"] || "cot"}

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
      <%!-- Collapsed header (always visible) --%>
      <div
        class="flex items-center gap-3 px-4 py-3 cursor-pointer"
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
        <div class="flex items-center gap-2 shrink-0">
          <.rank_pill rank={:apprentice} model={@member.ranks.apprentice.model} />
          <.rank_pill rank={:journeyman} model={@member.ranks.journeyman.model} />
          <.rank_pill rank={:master} model={@member.ranks.master.model} />
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
      </div>

      <%!-- Expanded body --%>
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
              <.rank_section rank={:apprentice} data={@member.ranks.apprentice} />
              <.rank_section rank={:journeyman} data={@member.ranks.journeyman} />
              <.rank_section rank={:master} data={@member.ranks.master} />
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
            <.rank_section rank={:apprentice} data={%{model: "", strategy: "cot"}} />
            <.rank_section rank={:journeyman} data={%{model: "", strategy: "cod"}} />
            <.rank_section rank={:master} data={%{model: "", strategy: "cod"}} />
          </div>
          <div class="flex justify-end gap-2 pt-2">
            <.button type="button" variant="outline" size="sm" phx-click="cancel_new">Cancel</.button>
            <.button type="submit" size="sm">Create Member</.button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  attr :rank, :atom, required: true
  attr :model, :string, required: true

  defp rank_pill(assigns) do
    color_classes =
      case assigns.rank do
        :apprentice -> "border-l-2 border-amber-700 bg-amber-50 text-amber-700"
        :journeyman -> "border-l-2 border-slate-400 bg-slate-100 text-slate-500"
        :master -> "border-l-2 border-yellow-500 bg-yellow-50 text-yellow-600"
      end

    label =
      case assigns.rank do
        :apprentice -> "Apprentice"
        :journeyman -> "Journeyman"
        :master -> "Master"
      end

    assigns = assign(assigns, color_classes: color_classes, label: label)

    ~H"""
    <span class={["flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium", @color_classes]}>
      <span class="font-bold">{@label}</span>
      <span class="opacity-75 max-w-20 truncate">{if @model == "", do: "—", else: @model}</span>
    </span>
    """
  end

  attr :rank, :atom, required: true
  attr :data, :map, required: true

  defp rank_section(assigns) do
    {label, border_class, text_class} =
      case assigns.rank do
        :apprentice -> {"Apprentice", "border-t-2 border-amber-700", "text-amber-700"}
        :journeyman -> {"Journeyman", "border-t-2 border-slate-400", "text-slate-500"}
        :master -> {"Master", "border-t-2 border-yellow-500", "text-yellow-600"}
      end

    rank_key = Atom.to_string(assigns.rank)
    assigns = assign(assigns, label: label, border_class: border_class, text_class: text_class, rank_key: rank_key)

    ~H"""
    <div class={["rounded p-3 bg-muted/30", @border_class]}>
      <div class={["text-xs font-semibold mb-2", @text_class]}>{@label}</div>
      <div class="space-y-2">
        <div>
          <label class="text-xs text-muted-foreground">Model</label>
          <.input
            type="text"
            name={"member[ranks][#{@rank_key}][model]"}
            value={@data.model}
            placeholder="model name"
            class="text-sm"
          />
        </div>
        <div>
          <label class="text-xs text-muted-foreground">Strategy</label>
          <select
            name={"member[ranks][#{@rank_key}][strategy]"}
            class="w-full text-sm border rounded px-2 py-1 bg-background"
          >
            <option value="cot" selected={@data.strategy == "cot"}>cot</option>
            <option value="cod" selected={@data.strategy == "cod"}>cod</option>
            <option value="default" selected={@data.strategy == "default"}>default</option>
          </select>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_expand", %{"id" => id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded, id) do
        MapSet.delete(socket.assigns.expanded, id)
      else
        MapSet.put(socket.assigns.expanded, id)
      end

    {:noreply, assign(socket, expanded: expanded)}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id, "active" => current_active}, socket) do
    new_active = current_active != "true"
    upsert_member_active(id, new_active, socket.assigns.members)
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
        "ranks" => parse_ranks(params["ranks"])
      }
    }

    case %ResourceDefinition{} |> ResourceDefinition.changeset(attrs) |> ExCellenceServer.Repo.insert() do
      {:ok, _} ->
        {:noreply, assign(socket, members: list_members(), adding_new: false)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create member")}
    end
  end

  @impl true
  def handle_event("save_member", %{"member" => params}, socket) do
    builtin = params["builtin"] == "true"
    id = params["id"]

    result =
      if builtin do
        save_builtin_member(id, params, socket.assigns.members)
      else
        save_custom_member(id, params)
      end

    case result do
      {:ok, _} ->
        {:noreply, assign(socket, members: list_members())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save member")}
    end
  end

  @impl true
  def handle_event("delete_member", %{"id" => id}, socket) do
    case ExCellenceServer.Repo.get(ResourceDefinition, id) do
      nil ->
        {:noreply, socket}

      resource ->
        ExCellenceServer.Repo.delete(resource)
        {:noreply, assign(socket, members: list_members())}
    end
  end

  defp upsert_member_active(id, new_active, members) do
    status = if new_active, do: "active", else: "draft"
    member = Enum.find(members, &(&1.id == id))

    if member && member.builtin do
      builtin = Member.get(id)

      case member.db_id && ExCellenceServer.Repo.get(ResourceDefinition, member.db_id) do
        nil ->
          %ResourceDefinition{}
          |> ResourceDefinition.changeset(%{
            type: "role",
            name: builtin.name,
            source: "code",
            status: status,
            config: %{
              "member_id" => id,
              "system_prompt" => builtin.system_prompt,
              "ranks" => ranks_to_config(builtin.ranks)
            }
          })
          |> ExCellenceServer.Repo.insert()

        db ->
          db
          |> ResourceDefinition.changeset(%{status: status})
          |> ExCellenceServer.Repo.update()
      end
    else
      case ExCellenceServer.Repo.get(ResourceDefinition, id) do
        nil -> {:ok, nil}
        db -> db |> ResourceDefinition.changeset(%{status: status}) |> ExCellenceServer.Repo.update()
      end
    end
  end

  defp save_builtin_member(slug, params, members) do
    builtin = Member.get(slug)
    member = Enum.find(members, &(&1.id == slug))

    config = %{
      "member_id" => slug,
      "system_prompt" => params["system_prompt"] || "",
      "ranks" => parse_ranks(params["ranks"])
    }

    case member && member.db_id && ExCellenceServer.Repo.get(ResourceDefinition, member.db_id) do
      nil ->
        %ResourceDefinition{}
        |> ResourceDefinition.changeset(%{
          type: "role",
          name: builtin.name,
          source: "code",
          status: "active",
          config: config
        })
        |> ExCellenceServer.Repo.insert()

      db ->
        db
        |> ResourceDefinition.changeset(%{config: config})
        |> ExCellenceServer.Repo.update()
    end
  end

  defp save_custom_member(id, params) do
    case ExCellenceServer.Repo.get(ResourceDefinition, id) do
      nil ->
        {:error, :not_found}

      db ->
        config = %{
          "system_prompt" => params["system_prompt"] || "",
          "ranks" => parse_ranks(params["ranks"])
        }

        db
        |> ResourceDefinition.changeset(%{name: params["name"] || db.name, config: config})
        |> ExCellenceServer.Repo.update()
    end
  end

  defp parse_ranks(nil), do: %{}

  defp parse_ranks(ranks_map) when is_map(ranks_map) do
    Map.new(ranks_map, fn {rank_key, v} ->
      {rank_key, %{"model" => v["model"] || "", "strategy" => v["strategy"] || "cot"}}
    end)
  end

  defp ranks_to_config(ranks) when is_map(ranks) do
    Map.new(ranks, fn {rank, data} ->
      {Atom.to_string(rank), %{"model" => data.model || "", "strategy" => data.strategy || "cot"}}
    end)
  end
end
