defmodule ExCalibur.ContextProviders.GuildCharter do
  @moduledoc """
  Prepends the guild's charter document to the evaluation input.
  Config: %{"guild_name" => "MyGuild"}
  """

  def build(%{"guild_name" => guild_name}, _quest, _input) when is_binary(guild_name) do
    case ExCalibur.GuildCharters.get_charter(guild_name) do
      nil -> ""
      "" -> ""
      text -> "## Guild Charter: #{guild_name}\n#{text}"
    end
  end

  def build(_, _, _), do: ""
end
