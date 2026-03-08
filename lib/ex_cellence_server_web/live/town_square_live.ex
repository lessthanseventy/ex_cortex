defmodule ExCellenceServerWeb.TownSquareLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import SaladUI.Badge

  alias Excellence.Schemas.ResourceDefinition
  alias ExCellenceServer.Evaluator
  alias ExCellenceServer.Members.Member

  @impl true
  def mount(_params, _session, socket) do
    has_guild = Evaluator.current_guild() != nil

    {:ok,
     assign(socket,
       page_title: "Town Square",
       editors: Member.editors(),
       analysts: Member.analysts(),
       specialists: Member.specialists(),
       advisors: Member.advisors(),
       has_guild: has_guild
     )}
  end

  @impl true
  def handle_event("recruit", %{"member-id" => member_id, "rank" => rank}, socket) do
    member = Member.get(member_id)
    rank_atom = String.to_existing_atom(rank)
    rank_config = member.ranks[rank_atom]

    attrs = %{
      type: "role",
      name: member.id,
      status: "draft",
      source: "db",
      config: %{
        "system_prompt" => member.system_prompt,
        "perspectives" => [
          %{
            "name" => rank,
            "model" => rank_config.model,
            "strategy" => rank_config.strategy
          }
        ],
        "parse_strategy" => "default"
      }
    }

    %ResourceDefinition{}
    |> ResourceDefinition.changeset(attrs)
    |> ExCellenceServer.Repo.insert(on_conflict: :nothing)

    {:noreply,
     socket
     |> put_flash(:info, "#{member.name} (#{rank}) recruited!")
     |> push_navigate(to: "/members")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div>
        <h1 class="text-2xl font-bold">Town Square</h1>
        <p class="text-muted-foreground mt-1">
          Recruit individual members — pick a role and rank.
        </p>
      </div>

      <%= unless @has_guild do %>
        <div class="rounded-lg border p-4">
          <p class="text-muted-foreground text-sm">
            No guild installed yet. Visit the <a href="/guild-hall" class="underline">Guild Hall</a>
            to install a guild first.
          </p>
        </div>
      <% end %>

      <.member_section
        title="Editors"
        description="Text quality and writing review"
        members={@editors}
        has_guild={@has_guild}
      />
      <.member_section
        title="Analysts"
        description="Data interpretation and pattern recognition"
        members={@analysts}
        has_guild={@has_guild}
      />
      <.member_section
        title="Specialists"
        description="Domain-specific technical expertise"
        members={@specialists}
        has_guild={@has_guild}
      />
      <.member_section
        title="Advisors"
        description="Perspective, judgment, and risk assessment"
        members={@advisors}
        has_guild={@has_guild}
      />
    </div>
    """
  end

  defp member_section(assigns) do
    ~H"""
    <div>
      <h2 class="text-lg font-semibold mb-1">{@title}</h2>
      <p class="text-muted-foreground text-sm mb-4">{@description}</p>
      <div class="space-y-2">
        <%= for member <- @members do %>
          <.member_row member={member} has_guild={@has_guild} />
        <% end %>
      </div>
    </div>
    """
  end

  defp member_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between rounded-lg border p-4">
      <div class="space-y-1">
        <div class="flex items-center gap-2">
          <span class="font-medium">{@member.name}</span>
          <.badge variant="secondary">{@member.category}</.badge>
        </div>
        <p class="text-sm text-muted-foreground">{@member.description}</p>
      </div>
      <div class="ml-4 shrink-0 flex gap-2">
        <.button
          size="sm"
          variant="outline"
          phx-click="recruit"
          phx-value-member-id={@member.id}
          phx-value-rank="apprentice"
          disabled={!@has_guild}
        >
          Apprentice
        </.button>
        <.button
          size="sm"
          variant="outline"
          phx-click="recruit"
          phx-value-member-id={@member.id}
          phx-value-rank="journeyman"
          disabled={!@has_guild}
        >
          Journeyman
        </.button>
        <.button
          size="sm"
          phx-click="recruit"
          phx-value-member-id={@member.id}
          phx-value-rank="master"
          disabled={!@has_guild}
        >
          Master
        </.button>
      </div>
    </div>
    """
  end
end
