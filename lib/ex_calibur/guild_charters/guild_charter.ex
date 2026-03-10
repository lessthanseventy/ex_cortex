defmodule ExCalibur.GuildCharters.GuildCharter do
  use Ecto.Schema
  import Ecto.Changeset

  schema "guild_charters" do
    field :guild_name, :string
    field :charter_text, :string, default: ""
    timestamps()
  end

  def changeset(charter, attrs) do
    charter
    |> cast(attrs, [:guild_name, :charter_text])
    |> validate_required([:guild_name])
  end
end
