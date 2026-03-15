defmodule ExCortex.Clusters do
  @moduledoc false
  import Ecto.Query

  alias ExCortex.Clusters.Cluster
  alias ExCortex.Repo

  def get_charter(guild_name) do
    case Repo.get_by(Cluster, guild_name: guild_name) do
      nil -> nil
      pathway -> pathway.charter_text
    end
  end

  def upsert_charter(guild_name, charter_text) do
    %Cluster{}
    |> Cluster.changeset(%{guild_name: guild_name, charter_text: charter_text})
    |> Repo.insert(
      on_conflict: [set: [charter_text: charter_text, updated_at: DateTime.utc_now()]],
      conflict_target: :guild_name,
      returning: true
    )
  end

  def list_charters do
    Repo.all(from c in Cluster, order_by: c.guild_name)
  end
end
