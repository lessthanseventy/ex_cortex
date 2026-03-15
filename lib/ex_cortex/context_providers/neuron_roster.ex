defmodule ExCortex.ContextProviders.NeuronRoster do
  @moduledoc """
  Injects the current list of active cluster neurons as prompt context.

  Useful for meta-thoughts that need to know what agents exist, their ranks,
  models, and tool access — without the model querying the database.

  Config:
    "team"  - optional team filter (default: all active role neurons)
    "label" - section header (default: "## cluster neurons")

  Example:
    %{"type" => "member_roster"}
    %{"type" => "member_roster", "team" => "dev"}
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  import Ecto.Query

  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo

  @impl true
  def build(config, _quest, _input) do
    label = Map.get(config, "label", "## cluster neurons")
    team = Map.get(config, "team")

    query =
      from m in Neuron,
        where: m.type == "role" and m.status == "active",
        order_by: [asc: m.name]

    query = if team, do: where(query, [m], m.team == ^team), else: query

    neurons = Repo.all(query)

    if neurons == [] do
      ""
    else
      rows =
        Enum.map(neurons, fn m ->
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
