defmodule ExCalibur.GuildCharters do
  @moduledoc false
  import Ecto.Query

  alias ExCalibur.GuildCharters.GuildCharter
  alias ExCalibur.Repo

  def get_charter(guild_name) do
    case Repo.get_by(GuildCharter, guild_name: guild_name) do
      nil -> nil
      charter -> charter.charter_text
    end
  end

  def upsert_charter(guild_name, charter_text) do
    %GuildCharter{}
    |> GuildCharter.changeset(%{guild_name: guild_name, charter_text: charter_text})
    |> Repo.insert(
      on_conflict: [set: [charter_text: charter_text, updated_at: DateTime.utc_now()]],
      conflict_target: :guild_name,
      returning: true
    )
  end

  def list_charters do
    Repo.all(from c in GuildCharter, order_by: c.guild_name)
  end
end
