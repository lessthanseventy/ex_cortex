defmodule ExCortexTUI.Screens.Neurons do
  @moduledoc "Neurons screen: lists clusters and the neurons (neurons) within each."

  @behaviour ExCortexTUI.Screen

  alias ExCortexTUI.Components.KeyHints
  alias ExCortexTUI.Components.Panel
  alias ExCortexTUI.Components.Status

  @impl true
  def init(_), do: %{}

  @impl true
  def handle_key(_key, state), do: {:noreply, state}

  @impl true
  def render(_state) do
    content = fetch_neurons()

    hints =
      KeyHints.render([
        {"c", "Cortex"},
        {"t", "Thoughts"},
        {"m", "Memory"},
        {"s", "Senses"},
        {"q", "Quit"}
      ])

    Enum.join([Panel.render("Neurons by Cluster", content), "", hints], "\n")
  end

  defp fetch_neurons do
    clusters = ExCortex.Clusters.list_pathways()

    if Enum.empty?(clusters) do
      Status.render(:amber, "No clusters installed")
    else
      Enum.map_join(clusters, "\n\n", fn cluster ->
        neurons = Map.get(cluster, :neurons, [])
        header = Status.render(:cyan, cluster.name)

        rows =
          if Enum.empty?(neurons) do
            "  (no neurons)"
          else
            Enum.map_join(neurons, "\n", fn m ->
              role = Map.get(m, :type, "neuron")
              "  • #{m.name}  [#{role}]"
            end)
          end

        header <> "\n" <> rows
      end)
    end
  rescue
    _ -> Status.render(:red, "Unavailable — DB not connected")
  end
end
