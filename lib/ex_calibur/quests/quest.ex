defmodule ExCalibur.Quests.Quest do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "excellence_quests" do
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
    :min_rank
  ]

  def changeset(quest, attrs) do
    quest
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["active", "paused"])
    |> validate_inclusion(:trigger, ["manual", "source", "scheduled"])
    |> validate_inclusion(:output_type, ["verdict", "artifact", "slack", "webhook", "github_issue", "github_pr", "email", "pagerduty"])
    |> validate_inclusion(:write_mode, ["append", "replace", "both"])
    |> validate_inclusion(:min_rank, ~w(apprentice journeyman master),
      message: "must be apprentice, journeyman, or master"
    )
    |> unique_constraint(:name)
  end
end
