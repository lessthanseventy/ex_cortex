defmodule ExCortex.Thoughts.Thought do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "thoughts" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "active"
    field :trigger, :string, default: "manual"
    field :schedule, :string
    field :run_at, :utc_datetime
    field :steps, {:array, :map}, default: []
    field :source_ids, {:array, :string}, default: []
    field :engram_trigger_tags, {:array, :string}, default: []
    field :signal_trigger_types, {:array, :string}, default: []
    field :signal_trigger_tags, {:array, :string}, default: []
    timestamps()
  end

  @required [:name, :trigger]
  @optional [
    :description,
    :status,
    :schedule,
    :run_at,
    :steps,
    :source_ids,
    :engram_trigger_tags,
    :signal_trigger_types,
    :signal_trigger_tags
  ]

  def changeset(thought, attrs) do
    thought
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["active", "paused", "done"])
    |> validate_inclusion(:trigger, ["manual", "source", "scheduled", "once", "memory", "cortex"])
    |> unique_constraint(:name)
  end
end
