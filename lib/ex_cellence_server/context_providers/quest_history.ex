defmodule ExCellenceServer.ContextProviders.QuestHistory do
  @moduledoc """
  Injects recent quest run results for the same quest into the preamble.
  Config: %{"type" => "quest_history", "limit" => 5}
  """

  @behaviour ExCellenceServer.ContextProviders.ContextProvider

  import Ecto.Query

  alias ExCellenceServer.Quests.QuestRun
  alias ExCellenceServer.Repo

  @impl true
  def build(config, quest, _input) do
    limit = Map.get(config, "limit", 5)
    quest_id = quest[:id] || quest["id"]

    if is_nil(quest_id) do
      ""
    else
      runs =
        Repo.all(
          from r in QuestRun,
            where: r.quest_id == ^quest_id and r.status == "complete",
            order_by: [desc: r.inserted_at],
            limit: ^limit,
            select: {r.inserted_at, r.results}
        )

      if runs == [] do
        ""
      else
        lines =
          Enum.map(runs, fn {ts, results} ->
            verdict = get_in(results, ["verdict"]) || "unknown"
            "- #{Calendar.strftime(ts, "%Y-%m-%d")}: #{verdict}"
          end)

        """
        ## Recent Quest History (last #{length(runs)} runs)
        #{Enum.join(lines, "\n")}
        """
        |> String.trim()
      end
    end
  end
end
