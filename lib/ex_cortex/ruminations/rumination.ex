defmodule ExCortex.Ruminations.Rumination do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "ruminations" do
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
    field :dedup_strategy, :string, default: "none"
    field :max_iterations, :integer, default: 1
    field :keyword_patterns, {:array, :string}, default: []
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
    :signal_trigger_tags,
    :dedup_strategy,
    :max_iterations,
    :keyword_patterns
  ]

  def changeset(rumination, attrs) do
    rumination
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["active", "paused", "done"])
    |> validate_inclusion(:trigger, ["manual", "source", "scheduled", "once", "memory", "cortex", "keyword"])
    |> validate_inclusion(:dedup_strategy, ["none", "concurrent"])
    |> unique_constraint(:name)
  end
end
