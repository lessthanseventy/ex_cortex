defmodule ExCortex.ContextProviders.ClusterPathway do
  @moduledoc """
  Prepends the cluster's pathway document to the evaluation input.
  Config: %{"cluster_name" => "MyCluster"}
  """

  def build(%{"cluster_name" => cluster_name}, _thought, _input) when is_binary(cluster_name) do
    case ExCortex.Clusters.get_pathway(cluster_name) do
      nil -> ""
      "" -> ""
      text -> "## Cluster Pathway: #{cluster_name}\n#{text}"
    end
  end

  def build(_, _, _), do: ""
end
