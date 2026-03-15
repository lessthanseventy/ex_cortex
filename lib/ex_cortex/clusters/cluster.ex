defmodule ExCortex.Clusters.Cluster do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "clusters" do
    field :cluster_name, :string
    field :pathway_text, :string, default: ""
    timestamps()
  end

  def changeset(pathway, attrs) do
    pathway
    |> cast(attrs, [:cluster_name, :pathway_text])
    |> validate_required([:cluster_name])
  end
end
