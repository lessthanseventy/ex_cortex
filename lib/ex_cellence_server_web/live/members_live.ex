defmodule ExCellenceServerWeb.MembersLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import SaladUI.Badge
  import SaladUI.Card

  alias Excellence.Schemas.ResourceDefinition

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
      ExCellenceServer.Members.Member.all()
      |> Enum.map(fn m ->
        db = Map.get(db_by_member_id, m.id)
        to_unified(m, db)
      end)

    customs =
      Enum.map(db_custom, &to_unified_custom/1)

    (builtins ++ customs)
    |> Enum.sort_by(fn m -> {if(m.active, do: 0, else: 1), if(m.builtin, do: 0, else: 1), m.name} end)
  end

  defp to_unified(%ExCellenceServer.Members.Member{} = m, nil) do
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

  defp to_unified(%ExCellenceServer.Members.Member{} = m, db) do
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
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Members</h1>
        <.link navigate="/members/new">
          <.button>New Member</.button>
        </.link>
      </div>

      <div class="grid gap-4">
        <%= for member <- @members do %>
          <.card>
            <.card_header>
              <div class="flex items-center justify-between">
                <.card_title>{member.name}</.card_title>
                <.badge variant={if member.active, do: "default", else: "secondary"}>
                  {if member.active, do: "active", else: "inactive"}
                </.badge>
              </div>
            </.card_header>
          </.card>
        <% end %>
      </div>
    </div>
    """
  end

end
