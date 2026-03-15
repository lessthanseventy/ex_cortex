defmodule ExCortex.Signals.Version do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "signal_versions" do
    field :body, :string
    field :metadata, :map, default: %{}
    field :replaced_at, :utc_datetime

    belongs_to :card, ExCortex.Signals.Signal
  end

  def changeset(version, attrs) do
    version
    |> cast(attrs, [:card_id, :body, :metadata, :replaced_at])
    |> validate_required([:card_id, :replaced_at])
  end
end
