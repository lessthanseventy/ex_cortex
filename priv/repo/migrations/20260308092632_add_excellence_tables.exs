defmodule ExCellenceServer.Repo.Migrations.AddExcellenceTables do
  use Ecto.Migration

  def change do
    # Resource definitions
    create table(:excellence_members) do
      add :type, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :config, :map, default: %{}
      add :source, :string, null: false, default: "db"
      add :version, :integer, default: 1
      add :created_by, :string
      timestamps()
    end

    create unique_index(:excellence_members, [:type, :name])
    create index(:excellence_members, [:type, :status])

    # Decisions
    create table(:excellence_decisions) do
      add :input_hash, :string
      add :action, :string
      add :confidence, :float
      add :verdicts, {:array, :map}, default: []
      add :role_results, {:array, :map}, default: []
      add :escalated, :boolean, default: false
      add :guard_blocked, :boolean, default: false
      add :metadata, :map, default: %{}
      timestamps()
    end

    # Outcomes
    create table(:excellence_outcomes) do
      add :decision_id, references(:excellence_decisions, on_delete: :delete_all)
      add :status, :string, default: "pending"
      add :result, :map, default: %{}
      add :resolved_at, :utc_datetime
      add :resolver, :string
      timestamps()
    end

    # Lessons
    create table(:excellence_lessons) do
      add :dimension_key, :string
      add :lesson_type, :string
      add :summary, :string
      add :outcome_stats, :map, default: %{}
      add :confidence, :float, default: 0.2
      add :win_rate, :float
      add :sample_size, :integer, default: 0
      add :active, :boolean, default: true
      add :source_decision_ids, {:array, :integer}, default: []
      add :metadata, :map, default: %{}
      timestamps()
    end

    create index(:excellence_lessons, [:dimension_key, :lesson_type])
    create index(:excellence_lessons, [:active])

    # Profiles
    create table(:excellence_profiles) do
      add :context_key, :string
      add :params, :map, default: %{}
      add :score, :float, default: 0.0
      add :sample_size, :integer, default: 0
      add :active, :boolean, default: false
      add :metadata, :map, default: %{}
      timestamps()
    end

    create unique_index(:excellence_profiles, [:context_key])

    # Tuning events
    create table(:excellence_tuning_events) do
      add :profile_id, references(:excellence_profiles, on_delete: :delete_all)
      add :event_type, :string
      add :param_name, :string
      add :old_value, :string
      add :new_value, :string
      add :evidence, :map, default: %{}
      timestamps()
    end

    # Discovered rules
    create table(:excellence_discovered_rules) do
      add :name, :string
      add :conditions, {:array, :map}
      add :action_type, :string
      add :status, :string, default: "candidate"
      add :confidence_base, :float
      add :stats, :map, default: %{}
      add :shadow_stats, :map, default: %{}
      add :live_stats, :map, default: %{}
      add :discovered_from, :map, default: %{}
      add :metadata, :map, default: %{}
      timestamps()
    end

    create unique_index(:excellence_discovered_rules, [:name])

    # Audit log
    create table(:excellence_audit_log) do
      add :resource_type, :string
      add :resource_name, :string
      add :action, :string
      add :details, :map, default: %{}
      add :actor, :string
      timestamps(updated_at: false)
    end

    create index(:excellence_audit_log, [:resource_type, :resource_name])
  end
end
