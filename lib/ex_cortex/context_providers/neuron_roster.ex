defmodule ExCortex.ContextProviders.NeuronRoster do
  @moduledoc """
  Injects the current list of active cluster neurons as prompt context.

  Useful for meta-thoughts that need to know what agents exist, their ranks,
  models, and tool access — without the model querying the database.

  Config:
    "team"  - optional team filter (default: all active role neurons)
    "label" - section header (default: "## cluster neurons")

  Example:
    %{"type" => "neuron_roster"}
    %{"type" => "neuron_roster", "team" => "dev"}
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  import Ecto.Query

  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo

  @impl true
  def build(config, _thought, _input) do
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
      rows = Enum.map(neurons, &format_neuron_row/1)
      "#{label}\n\n#{Enum.join(rows, "\n")}"
    end
  end

  defp format_neuron_row(m) do
    rank = m.config["rank"] || "?"
    model = m.config["model"] || "?"
    tools = format_tools(m.config["tools"])
    "- **#{m.name}** (#{rank}) — #{model} — tools: #{tools}"
  end

  defp format_tools(nil), do: "none"
  defp format_tools(list) when is_list(list), do: Enum.join(list, ", ")
  defp format_tools(preset) when is_binary(preset), do: preset
  defp format_tools(_), do: "?"
end
