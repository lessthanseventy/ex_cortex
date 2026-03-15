defmodule ExCortex.ContextProviders.NeuronStats do
  @moduledoc """
  Injects a summary of active neuron roster (names, ranks, teams) into the preamble.
  Config: %{"type" => "member_stats"}
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  import Ecto.Query

  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo

  @impl true
  def build(_config, _quest, _input) do
    neurons =
      Repo.all(
        from m in Neuron,
          where: m.type == "role" and m.status == "active",
          select: {m.name, m.team, m.config},
          order_by: m.name
      )

    if neurons == [] do
      ""
    else
      lines = Enum.map(neurons, &format_member/1)

      String.trim("""
      ## Active Neurons (#{length(neurons)})
      #{Enum.join(lines, "\n")}
      """)
    end
  end

  defp format_member({name, team, config}) do
    rank = (config || %{})["rank"] || "journeyman"
    team_str = if team, do: " [#{team}]", else: ""
    "- #{name} (#{rank})#{team_str}"
  end
end
