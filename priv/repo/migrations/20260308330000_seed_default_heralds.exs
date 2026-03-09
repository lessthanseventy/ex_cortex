defmodule ExCalibur.Repo.Migrations.SeedDefaultHeralds do
  use Ecto.Migration

  def up do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    defaults = [
      %{name: "slack:default", type: "slack", config: %{}},
      %{name: "webhook:default", type: "webhook", config: %{}},
      %{name: "github_issue:default", type: "github_issue", config: %{}},
      %{name: "github_pr:default", type: "github_pr", config: %{}},
      %{name: "email:default", type: "email", config: %{}},
      %{name: "pagerduty:default", type: "pagerduty", config: %{}}
    ]

    rows =
      Enum.map(defaults, fn herald ->
        [
          name: herald.name,
          type: herald.type,
          config: herald.config,
          inserted_at: now,
          updated_at: now
        ]
      end)

    repo().insert_all("heralds", rows, on_conflict: :nothing)
  end

  def down do
    import Ecto.Query

    repo().delete_all(
      from(h in "heralds",
        where: h.name in ["slack:default", "webhook:default", "github_issue:default", "github_pr:default", "email:default", "pagerduty:default"]
      )
    )
  end
end
