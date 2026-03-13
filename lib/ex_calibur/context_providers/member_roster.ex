defmodule ExCalibur.ContextProviders.MemberRoster do
  @moduledoc """
  Injects the current list of active guild members as prompt context.

  Useful for meta-quests that need to know what agents exist, their ranks,
  models, and tool access — without the model querying the database.

  Config:
    "team"  - optional team filter (default: all active role members)
    "label" - section header (default: "## Guild Members")

  Example:
    %{"type" => "member_roster"}
    %{"type" => "member_roster", "team" => "dev"}
  """

  @behaviour ExCalibur.ContextProviders.ContextProvider

  import Ecto.Query

  alias ExCalibur.Repo
  alias ExCalibur.Schemas.Member

  @impl true
  def build(config, _quest, _input) do
    label = Map.get(config, "label", "## Guild Members")
    team = Map.get(config, "team")

    query =
      from m in Member,
        where: m.type == "role" and m.status == "active",
        order_by: [asc: m.name]

    query = if team, do: where(query, [m], m.team == ^team), else: query

    members = Repo.all(query)

    if members == [] do
      ""
    else
      rows =
        Enum.map(members, fn m ->
          rank = m.config["rank"] || "?"
          model = m.config["model"] || "?"

          tools =
            case m.config["tools"] do
              nil -> "none"
              list when is_list(list) -> Enum.join(list, ", ")
              preset when is_binary(preset) -> preset
              _ -> "?"
            end

          "- **#{m.name}** (#{rank}) — #{model} — tools: #{tools}"
        end)

      "#{label}\n\n#{Enum.join(rows, "\n")}"
    end
  end
end
