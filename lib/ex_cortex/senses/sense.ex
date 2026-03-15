defmodule ExCortex.Senses.Sense do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "senses" do
    field :name, :string
    field :source_type, :string
    field :config, :map, default: %{}
    field :state, :map, default: %{}
    field :status, :string, default: "active"
    field :last_run_at, :utc_datetime
    field :error_message, :string
    field :book_id, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:name, :source_type, :config, :state, :status, :last_run_at, :error_message, :book_id])
    |> validate_required([:source_type])
    |> validate_inclusion(
      :source_type,
      ~w(git directory feed webhook url websocket cortex obsidian email media github_issues nextcloud)
    )
    |> validate_inclusion(:status, ~w(active paused error))
  end
end
