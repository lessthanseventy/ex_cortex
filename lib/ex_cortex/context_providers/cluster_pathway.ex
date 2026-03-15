defmodule ExCortex.ContextProviders.ClusterPathway do
  @moduledoc """
  Prepends the cluster's pathway document to the evaluation input.
  Config: %{"guild_name" => "MyGuild"}
  """

  def build(%{"guild_name" => guild_name}, _quest, _input) when is_binary(guild_name) do
    case ExCortex.Clusters.get_charter(guild_name) do
      nil -> ""
      "" -> ""
      text -> "## Cluster Pathway: #{guild_name}\n#{text}"
    end
  end

  def build(_, _, _), do: ""
end
