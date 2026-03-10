defmodule ExCalibur.Repo.Migrations.RenameQuestCampaignTables do
  use Ecto.Migration

  def up do
    # Drop FK constraints before renaming tables
    # excellence_quest_runs.quest_id → excellence_quests
    execute "ALTER TABLE excellence_quest_runs DROP CONSTRAINT IF EXISTS excellence_quest_runs_quest_id_fkey"
    # excellence_campaign_runs.campaign_id → excellence_campaigns
    execute "ALTER TABLE excellence_campaign_runs DROP CONSTRAINT IF EXISTS excellence_campaign_runs_campaign_id_fkey"
    # excellence_proposals.quest_id → excellence_quests
    execute "ALTER TABLE excellence_proposals DROP CONSTRAINT IF EXISTS excellence_proposals_quest_id_fkey"
    # excellence_proposals.quest_run_id → excellence_quest_runs
    execute "ALTER TABLE excellence_proposals DROP CONSTRAINT IF EXISTS excellence_proposals_quest_run_id_fkey"

    # Rename excellence_quests → excellence_steps
    rename table(:excellence_quests), to: table(:excellence_steps)

    # Rename excellence_quest_runs → excellence_step_runs
    rename table(:excellence_quest_runs), to: table(:excellence_step_runs)

    # Rename excellence_campaigns → excellence_quests
    rename table(:excellence_campaigns), to: table(:excellence_quests)

    # Rename excellence_campaign_runs → excellence_quest_runs
    rename table(:excellence_campaign_runs), to: table(:excellence_quest_runs)

    # Rename columns in excellence_step_runs (was excellence_quest_runs)
    # quest_id → step_id
    rename table(:excellence_step_runs), :quest_id, to: :step_id
    # campaign_run_id → quest_run_id
    rename table(:excellence_step_runs), :campaign_run_id, to: :quest_run_id

    # Rename column in excellence_quest_runs (was excellence_campaign_runs)
    # campaign_id → quest_id
    rename table(:excellence_quest_runs), :campaign_id, to: :quest_id

    # Restore FK constraints with correct table references
    execute "ALTER TABLE excellence_step_runs ADD CONSTRAINT excellence_step_runs_step_id_fkey FOREIGN KEY (step_id) REFERENCES excellence_steps(id) ON DELETE CASCADE"

    execute "ALTER TABLE excellence_quest_runs ADD CONSTRAINT excellence_quest_runs_quest_id_fkey FOREIGN KEY (quest_id) REFERENCES excellence_quests(id) ON DELETE CASCADE"

    execute "ALTER TABLE excellence_proposals ADD CONSTRAINT excellence_proposals_quest_id_fkey FOREIGN KEY (quest_id) REFERENCES excellence_steps(id) ON DELETE CASCADE"

    # Rename unique index on excellence_steps (was excellence_quests)
    execute "ALTER INDEX IF EXISTS excellence_quests_name_index RENAME TO excellence_steps_name_index"
    # Rename unique index on excellence_quests (was excellence_campaigns)
    execute "ALTER INDEX IF EXISTS excellence_campaigns_name_index RENAME TO excellence_quests_name_index"
  end

  def down do
    # Reverse the migration
    execute "ALTER TABLE excellence_step_runs DROP CONSTRAINT IF EXISTS excellence_step_runs_step_id_fkey"

    execute "ALTER TABLE excellence_quest_runs DROP CONSTRAINT IF EXISTS excellence_quest_runs_quest_id_fkey"

    execute "ALTER TABLE excellence_proposals DROP CONSTRAINT IF EXISTS excellence_proposals_quest_id_fkey"

    rename table(:excellence_quest_runs), :quest_id, to: :campaign_id
    rename table(:excellence_step_runs), :step_id, to: :quest_id
    rename table(:excellence_step_runs), :quest_run_id, to: :campaign_run_id

    rename table(:excellence_quest_runs), to: table(:excellence_campaign_runs)
    rename table(:excellence_quests), to: table(:excellence_campaigns)
    rename table(:excellence_step_runs), to: table(:excellence_quest_runs)
    rename table(:excellence_steps), to: table(:excellence_quests)

    execute "ALTER TABLE excellence_quest_runs ADD CONSTRAINT excellence_quest_runs_quest_id_fkey FOREIGN KEY (quest_id) REFERENCES excellence_quests(id) ON DELETE CASCADE"

    execute "ALTER TABLE excellence_campaign_runs ADD CONSTRAINT excellence_campaign_runs_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES excellence_campaigns(id) ON DELETE CASCADE"

    execute "ALTER TABLE excellence_proposals ADD CONSTRAINT excellence_proposals_quest_id_fkey FOREIGN KEY (quest_id) REFERENCES excellence_quests(id) ON DELETE CASCADE"

    execute "ALTER INDEX IF EXISTS excellence_steps_name_index RENAME TO excellence_quests_name_index"

    execute "ALTER INDEX IF EXISTS excellence_quests_name_index RENAME TO excellence_campaigns_name_index"
  end
end
