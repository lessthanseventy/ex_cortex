defmodule ExCortex.Thoughts.Synapse do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "synapses" do
    field :name, :string
    field :description, :string
    field :status, :string
    field :trigger, :string
    field :schedule, :string
    field :roster, {:array, :map}, default: []
    field :context_providers, {:array, :map}, default: []
    field :source_ids, {:array, :string}, default: []
    field :output_type, :string, default: "verdict"
    field :write_mode, :string, default: "append"
    field :entry_title_template, :string
    field :log_title_template, :string
    field :herald_name, :string
    field :min_rank, :string
    field :lore_tags, {:array, :string}, default: []
    # Escalate mode — rank ladder retry
    field :escalate, :boolean, default: false
    field :escalate_threshold, :float, default: 0.6
    field :escalate_on_verdict, {:array, :string}, default: []
    # Reflect mode — tool-assisted context gathering + retry
    field :loop_mode, :string
    field :loop_tools, {:array, :string}, default: []
    field :reflect_threshold, :float, default: 0.6
    field :reflect_on_verdict, {:array, :string}, default: []
    field :max_iterations, :integer, default: 3
    field :pin_slug, :string
    field :pin_order, :integer, default: 0
    field :cards, :map, default: %{}
    field :guild_name, :string
    field :dangerous_tool_mode, :string, default: "execute"
    field :max_tool_iterations, :integer, default: 15
    timestamps()
  end

  @required [:name, :trigger]
  @optional [
    :description,
    :status,
    :schedule,
    :roster,
    :context_providers,
    :source_ids,
    :output_type,
    :write_mode,
    :entry_title_template,
    :log_title_template,
    :herald_name,
    :min_rank,
    :lore_tags,
    :escalate,
    :escalate_threshold,
    :escalate_on_verdict,
    :loop_mode,
    :loop_tools,
    :reflect_threshold,
    :reflect_on_verdict,
    :max_iterations,
    :pin_slug,
    :pin_order,
    :cards,
    :guild_name,
    :dangerous_tool_mode,
    :max_tool_iterations
  ]

  def changeset(step, attrs) do
    step
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["active", "paused"])
    |> validate_inclusion(:trigger, ["manual", "source", "scheduled"])
    |> validate_inclusion(:output_type, [
      "verdict",
      "artifact",
      "freeform",
      "lodge_card",
      "slack",
      "webhook",
      "github_issue",
      "github_pr",
      "email",
      "pagerduty"
    ])
    |> validate_inclusion(:write_mode, ["append", "replace", "both"])
    |> validate_inclusion(:dangerous_tool_mode, ~w(execute intercept dry_run))
    |> validate_inclusion(:min_rank, ~w(apprentice journeyman master),
      message: "must be apprentice, journeyman, or master"
    )
    |> validate_inclusion(:loop_mode, ["reflect", "sequential", "parallel", "dynamic"],
      message: "must be reflect, sequential, parallel, or dynamic"
    )
    |> unique_constraint(:name)
  end
end
