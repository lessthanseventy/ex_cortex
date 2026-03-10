defmodule ExCalibur.ContextProviders.QuestHistory do
  @moduledoc """
  Injects recent step run results for the same step into the preamble.
  Config: %{"type" => "quest_history", "limit" => 5}
  """

  @behaviour ExCalibur.ContextProviders.ContextProvider

  import Ecto.Query

  alias ExCalibur.Quests.StepRun
  alias ExCalibur.Repo

  @impl true
  def build(config, step, _input) do
    limit = Map.get(config, "limit", 5)
    step_id = step[:id] || step["id"]

    if is_nil(step_id) do
      ""
    else
      runs =
        Repo.all(
          from r in StepRun,
            where: r.step_id == ^step_id and r.status == "complete",
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

        String.trim("""
        ## Recent Step History (last #{length(runs)} runs)
        #{Enum.join(lines, "\n")}
        """)
      end
    end
  end
end
