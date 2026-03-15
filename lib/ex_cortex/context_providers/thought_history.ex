defmodule ExCortex.ContextProviders.ThoughtHistory do
  @moduledoc """
  Injects recent step run results for the same step into the preamble.
  Config: %{"type" => "thought_history", "limit" => 5}
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  import Ecto.Query

  alias ExCortex.Repo
  alias ExCortex.Thoughts.Impulse

  @impl true
  def build(config, step, _input) do
    limit = Map.get(config, "limit", 5)
    step_id = step[:id] || step["id"]

    if is_nil(step_id) do
      ""
    else
      runs =
        Repo.all(
          from r in Impulse,
            where: r.synapse_id == ^step_id and r.status == "complete",
            order_by: [desc: r.inserted_at],
            limit: ^limit,
            select: {r.inserted_at, r.results}
        )

      if runs == [] do
        ""
      else
        lines = Enum.map(runs, &format_run/1)

        String.trim("""
        ## Recent Step History (last #{length(runs)} runs)
        #{Enum.join(lines, "\n")}
        """)
      end
    end
  end

  defp format_run({ts, results}) do
    verdict = get_in(results, ["verdict"]) || "unknown"
    "- #{Calendar.strftime(ts, "%Y-%m-%d")}: #{verdict}"
  end
end
