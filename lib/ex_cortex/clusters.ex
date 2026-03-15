defmodule ExCortex.Clusters do
  @moduledoc false
  import Ecto.Query

  alias ExCortex.Clusters.Cluster
  alias ExCortex.Repo

  def get_pathway(cluster_name) do
    case Repo.get_by(Cluster, cluster_name: cluster_name) do
      nil -> nil
      pathway -> pathway.pathway_text
    end
  end

  def upsert_pathway(cluster_name, pathway_text) do
    %Cluster{}
    |> Cluster.changeset(%{cluster_name: cluster_name, pathway_text: pathway_text})
    |> Repo.insert(
      on_conflict: [set: [pathway_text: pathway_text, updated_at: DateTime.utc_now()]],
      conflict_target: :cluster_name,
      returning: true
    )
  end

  def list_pathways do
    Repo.all(from c in Cluster, order_by: c.cluster_name)
  end
end
