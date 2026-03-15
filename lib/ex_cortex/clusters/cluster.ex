defmodule ExCortex.Clusters.Cluster do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "clusters" do
    field :guild_name, :string
    field :charter_text, :string, default: ""
    timestamps()
  end

  def changeset(pathway, attrs) do
    pathway
    |> cast(attrs, [:guild_name, :charter_text])
    |> validate_required([:guild_name])
  end
end
