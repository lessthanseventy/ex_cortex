defmodule ExCellenceServer.ContextProviders.MemberStats do
  @moduledoc """
  Injects a summary of active member roster (names, ranks, teams) into the preamble.
  Config: %{"type" => "member_stats"}
  """

  @behaviour ExCellenceServer.ContextProviders.ContextProvider

  import Ecto.Query

  alias Excellence.Schemas.Member
  alias ExCellenceServer.Repo

  @impl true
  def build(_config, _quest, _input) do
    members =
      Repo.all(
        from m in Member,
          where: m.type == "role" and m.status == "active",
          select: {m.name, m.team, m.config},
          order_by: m.name
      )

    if members == [] do
      ""
    else
      lines =
        Enum.map(members, fn {name, team, config} ->
          rank = (config || %{})["rank"] || "journeyman"
          team_str = if team, do: " [#{team}]", else: ""
          "- #{name} (#{rank})#{team_str}"
        end)

      String.trim("""
      ## Active Members (#{length(members)})
      #{Enum.join(lines, "\n")}
      """)
    end
  end
end
