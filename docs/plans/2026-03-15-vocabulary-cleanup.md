# Vocabulary Cleanup — Full Rename

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate all old vocabulary (guild, charter, lodge, quest, herald, lore, grimoire, library, town-square, member) from code, tests, infra, and routes. No legacy compatibility, no half measures.

**Architecture:** New Ecto migration renames remaining DB columns, then cascade changes through schemas → business logic → LiveViews → tests → infra. Delete legacy routes entirely.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto, PostgreSQL

---

## Column Rename Map

| Table | Old Column | New Column |
|-------|-----------|------------|
| clusters | guild_name | cluster_name |
| clusters | charter_text | pathway_text |
| synapses | herald_name | expression_name |
| synapses | lore_tags | engram_tags |
| synapses | guild_name | cluster_name |
| thoughts | lore_trigger_tags | engram_trigger_tags |
| thoughts | lodge_trigger_types | signal_trigger_types |
| thoughts | lodge_trigger_tags | signal_trigger_tags |
| signals | guild_name | cluster_name |
| senses | book_id | reflex_id |

## PubSub / Event Rename Map

| Old | New |
|-----|-----|
| `:lodge_card_posted` | `:signal_posted` |
| `:lore_updated` | `:engram_updated` |
| `:lore_entry_created` | `:engram_created` |

## Tool Rename Map

| Old | New |
|-----|-----|
| `query_lore` | `query_memory` |

## Function Rename Map

| Module | Old | New |
|--------|-----|-----|
| Clusters | `get_charter/1` | `get_pathway/1` |
| Clusters | `upsert_charter/2` | `upsert_pathway/2` |
| Clusters | `list_charters/0` | `list_pathways/0` |
| Obsidian.Sync | `sync_lodge_card/1` | `sync_signal/1` |
| Obsidian.Sync | `sync_lore_entry/1` | `sync_engram/1` |

## Route Cleanup

Remove all legacy routes. Keep only:
- `/`, `/cortex`, `/neurons`, `/thoughts`, `/memory`, `/senses`, `/instinct`, `/guide`, `/settings`, `/evaluate`

Delete: `/lodge`, `/quests`, `/quest-board`, `/thought-board`, `/town-square`, `/guild-hall`, `/cluster-hall`, `/grimoire`, `/library`

## File Rename Map

| Old Path | New Path |
|----------|----------|
| `lib/ex_cortex_web/live/lodge_live.ex` | `lib/ex_cortex_web/live/cortex_live.ex` (merge or delete — CortexLive already exists) |
| `lib/ex_cortex_web/live/quests_live.ex` | `lib/ex_cortex_web/live/thoughts_live.ex` (already exists — delete quests_live) |
| `lib/ex_cortex_web/live/guild_hall_live.ex` | `lib/ex_cortex_web/live/neurons_live.ex` (already exists — delete guild_hall_live) |
| `lib/ex_cortex_web/live/grimoire_live.ex` | delete (ThoughtsLive covers this) |
| `lib/ex_cortex_web/live/library_live.ex` | delete (MemoryLive covers this) |
| `lib/ex_cortex_web/live/town_square_live.ex` | delete (SensesLive covers this) |
| `lib/ex_cortex_web/components/lodge_cards.ex` | `lib/ex_cortex_web/components/signal_cards.ex` |
| `lib/ex_cortex_ui/components/charter_picker.ex` | `lib/ex_cortex_ui/components/pathway_picker.ex` |
| `lib/ex_cortex/workers/quest_worker.ex` | `lib/ex_cortex/workers/thought_worker.ex` |
| `lib/ex_cortex/tools/query_memory.ex` | (keep path, rename tool name inside) |
| `test/ex_cortex/lodge_test.exs` | `test/ex_cortex/signals_test.exs` |
| `test/ex_cortex/guild_charters_test.exs` | `test/ex_cortex/cluster_pathways_test.exs` |
| `test/ex_cortex/quest_runner_recording_test.exs` | `test/ex_cortex/thought_runner_recording_test.exs` |
| `test/ex_cortex/step_runner_herald_test.exs` | `test/ex_cortex/impulse_runner_expression_test.exs` |
| `test/ex_cortex/step_runner_lodge_card_test.exs` | `test/ex_cortex/impulse_runner_signal_test.exs` |
| `test/ex_cortex/sources/lodge_watcher_test.exs` | `test/ex_cortex/sources/signal_watcher_test.exs` |
| `test/ex_cortex_web/live/lodge_live_test.exs` | delete |
| `test/ex_cortex_web/live/guild_hall_live_test.exs` | delete |
| `test/ex_cortex_web/live/grimoire_live_test.exs` | delete |
| `test/ex_cortex_web/live/library_live_test.exs` | delete |
| `test/ex_cortex_web/live/town_square_live_test.exs` | delete |
| `test/ex_cortex_web/live/quests_live_test.exs` | delete |
| `test/ex_cortex_web/components/lodge_cards_test.exs` | `test/ex_cortex_web/components/signal_cards_test.exs` |
| `test/ex_cortex/tools/query_lore_test.exs` | `test/ex_cortex/tools/query_memory_test.exs` |

---

### Task 0: Delete stale ExCaliburWeb snapshots and old ExCortexWeb legacy snapshots

**Files:**
- Delete: all `test/excessibility/html_snapshots/Elixir_ExCaliburWeb_*` files
- Delete: all `test/excessibility/html_snapshots/Elixir_ExCortexWeb_{GuildHall,Grimoire,Lodge,TownSquare,Library,Quests}*` files

**Step 1: Delete the files**
```bash
rm test/excessibility/html_snapshots/Elixir_ExCaliburWeb_*
rm test/excessibility/html_snapshots/Elixir_ExCortexWeb_GuildHallLiveTest_*
rm test/excessibility/html_snapshots/Elixir_ExCortexWeb_GrimoireLiveTest_*
rm test/excessibility/html_snapshots/Elixir_ExCortexWeb_LodgeLiveTest_*
rm test/excessibility/html_snapshots/Elixir_ExCortexWeb_TownSquareLiveTest_*
rm test/excessibility/html_snapshots/Elixir_ExCortexWeb_LibraryLiveTest_*
rm test/excessibility/html_snapshots/Elixir_ExCortexWeb_QuestsLiveTest_*
```

**Step 2: Commit**

---

### Task 1: Fix infra files — rename ex_calibur references

**Files:**
- Modify: `docker-compose.yml`
- Modify: `.mise.toml`
- Modify: `bin/restart.sh`
- Modify: `docker/init-nextcloud.sh`

**Changes:**
- `docker-compose.yml`: `ex_calibur` → `ex_cortex` in POSTGRES_DB, healthcheck, dockerfile path, DATABASE_URL
- `.mise.toml`: `ex_calibur` → `ex_cortex` in DATABASE_URL
- `bin/restart.sh`: `.ex_calibur.pid` → `.ex_cortex.pid`
- `docker/init-nextcloud.sh`: `ExCalibur` → `ExCortex` in comment

**Step 1: Make the changes**
**Step 2: Commit**

---

### Task 2: Create DB migration to rename remaining columns

**Files:**
- Create: `priv/repo/migrations/20260315000000_rename_remaining_old_vocabulary.exs`

**Step 1: Write the migration**

```elixir
defmodule ExCortex.Repo.Migrations.RenameRemainingOldVocabulary do
  use Ecto.Migration

  def change do
    # clusters
    rename table(:clusters), :guild_name, to: :cluster_name
    rename table(:clusters), :charter_text, to: :pathway_text

    # synapses
    rename table(:synapses), :herald_name, to: :expression_name
    rename table(:synapses), :lore_tags, to: :engram_tags
    rename table(:synapses), :guild_name, to: :cluster_name

    # thoughts
    rename table(:thoughts), :lore_trigger_tags, to: :engram_trigger_tags
    rename table(:thoughts), :lodge_trigger_types, to: :signal_trigger_types
    rename table(:thoughts), :lodge_trigger_tags, to: :signal_trigger_tags

    # signals
    rename table(:signals), :guild_name, to: :cluster_name

    # senses
    rename table(:senses), :book_id, to: :reflex_id
  end
end
```

**Step 2: Run the migration**
```bash
mix ecto.migrate
```

**Step 3: Commit**

---

### Task 3: Update Ecto schemas to match renamed columns

**Files:**
- Modify: `lib/ex_cortex/clusters/cluster.ex` — `guild_name` → `cluster_name`, `charter_text` → `pathway_text`
- Modify: `lib/ex_cortex/thoughts/synapse.ex` — `herald_name` → `expression_name`, `lore_tags` → `engram_tags`, `guild_name` → `cluster_name`, `lodge_card` → `signal` in output_type validation
- Modify: `lib/ex_cortex/thoughts/thought.ex` — `lore_trigger_tags` → `engram_trigger_tags`, `lodge_trigger_types` → `signal_trigger_types`, `lodge_trigger_tags` → `signal_trigger_tags`
- Modify: `lib/ex_cortex/signals/signal.ex` — `guild_name` → `cluster_name`
- Modify: `lib/ex_cortex/senses/sense.ex` — `book_id` → `reflex_id`

**Step 1: Update all schema files**
**Step 2: Run tests to see what breaks**
**Step 3: Commit**

---

### Task 4: Update business logic modules — Clusters, Signals, Memory

**Files:**
- Modify: `lib/ex_cortex/clusters.ex` — rename `get_charter` → `get_pathway`, `upsert_charter` → `upsert_pathway`, `list_charters` → `list_pathways`, all `guild_name` → `cluster_name`, `charter_text` → `pathway_text`
- Modify: `lib/ex_cortex/signals.ex` — `:lodge_card_posted` → `:signal_posted`, `sync_lodge_card` → `sync_signal`
- Modify: `lib/ex_cortex/memory.ex` — `:lore_updated` → `:engram_updated`, `:lore_entry_created` → `:engram_created`
- Modify: `lib/ex_cortex/signals/trigger_runner.ex` — `lodge_trigger_types` → `signal_trigger_types`, `lodge_trigger_tags` → `signal_trigger_tags`, `:lodge_card_posted` → `:signal_posted`
- Modify: `lib/ex_cortex/memory/engram_trigger_runner.ex` — `lore_trigger_tags` → `engram_trigger_tags`, `:lore_entry_created` → `:engram_created`
- Modify: `lib/ex_cortex/obsidian/sync.ex` — `sync_lodge_card` → `sync_signal`, `sync_lore_entry` → `sync_engram`
- Modify: `lib/ex_cortex/senses/signal_watcher.ex` — any `lodge_card` references
- Modify: `lib/ex_cortex/senses/reflex.ex` — any `guild` references

**Step 1: Update all modules**
**Step 2: Run tests**
**Step 3: Commit**

---

### Task 5: Update Thoughts pipeline modules

**Files:**
- Modify: `lib/ex_cortex/thoughts/runner.ex` — `guild_name` → `cluster_name`, `lodge_card` → `signal`
- Modify: `lib/ex_cortex/thoughts/impulse_runner.ex` — `query_lore` → `query_memory`, `guild_name` → `cluster_name`, `herald_name` → `expression_name`, `lore_tags` → `engram_tags`, `lodge_card` → `signal`
- Modify: `lib/ex_cortex/workers/quest_worker.ex` — rename module to `ThoughtWorker`, update all references
- Modify: `lib/ex_cortex/evaluator.ex` — any `guild`/`quest` references

**Step 1: Update all files**
**Step 2: Run tests**
**Step 3: Commit**

---

### Task 6: Rename query_lore tool to query_memory

**Files:**
- Modify: `lib/ex_cortex/tools/query_memory.ex` — `name: "query_lore"` → `name: "query_memory"`
- Modify: `lib/ex_cortex/tools/registry.ex` — all `query_lore` references in docs
- Modify: all `lib/ex_cortex/pathways/*.ex` — `"query_lore"` → `"query_memory"` in every loop_tools list

**Step 1: Update tool name**
**Step 2: Update registry docs**
**Step 3: Update all pathways (bulk find/replace)**
**Step 4: Run tests**
**Step 5: Commit**

---

### Task 7: Update context providers

**Files:**
- Modify: `lib/ex_cortex/context_providers/context_provider.ex` — remove legacy `module_for` mappings (`quest_history` → `thought_history`, `quest_output` → `thought_output`, `member_stats` → `neuron_stats`, `member_roster` → `neuron_roster`, `guild_charter` → `cluster_pathway`), or replace with new names
- Modify: `lib/ex_cortex/context_providers/cluster_pathway.ex` — `guild_name` → `cluster_name`, `get_charter` → `get_pathway`
- Modify: all context_providers `build/3` signatures — `_quest` → `_thought` parameter name
- Modify: `lib/ex_cortex/context_providers/neuron_roster.ex` — `member_roster` → `neuron_roster` in docs
- Modify: `lib/ex_cortex/context_providers/neuron_stats.ex` — `member_stats` → `neuron_stats` in docs

**Step 1: Update context_provider.ex mappings**
**Step 2: Update all build/3 signatures**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 8: Update board definitions

**Files:**
- Modify: `lib/ex_cortex/board/lifestyle.ex` — `lore_tags` → `engram_tags`, `lodge_card` → `signal`, `lodge_trigger_types` → `signal_trigger_types`, `book_id` → `reflex_id`, `quest_definition` → `thought_definition`, `grimoire` → `memory` in strings
- Modify: `lib/ex_cortex/board/review.ex` — `herald_type` → `expression_type`, `herald_name` → `expression_name`
- Modify: `lib/ex_cortex/board/triage.ex` — same herald → expression renames
- Modify: `lib/ex_cortex/board/onboarding.ex` — same herald → expression renames
- Modify: `lib/ex_cortex/board/reporting.ex` — `quest_definition` → `thought_definition`
- Modify: `lib/ex_cortex/board/generation.ex` — `quest_definition` → `thought_definition`
- Modify: `lib/ex_cortex/board.ex` — `quest_definition` → `thought_definition`
- Modify: all other board files with `quest_definition` references

**Step 1: Update all board files**
**Step 2: Run tests**
**Step 3: Commit**

---

### Task 9: Update all pathways

**Files:**
- Modify: all `lib/ex_cortex/pathways/*.ex` — `quest_definition` → `thought_definition`, `herald_type` → `expression_type`, `herald_name` → `expression_name`, `guild` → `cluster`, `lore_tags` → `engram_tags`, `lodge_card` → `signal`, `lodge_trigger_types` → `signal_trigger_types`

**Step 1: Bulk replace across all pathway files**
**Step 2: Run tests**
**Step 3: Commit**

---

### Task 10: Update LiveViews and components

**Files:**
- Modify: `lib/ex_cortex_web/live/cortex_live.ex` — `:lodge_card_posted` → `:signal_posted`, any lodge/guild refs
- Modify: `lib/ex_cortex_web/live/neurons_live.ex` — any guild/charter refs
- Modify: `lib/ex_cortex_web/live/memory_live.ex` — any lore refs
- Modify: `lib/ex_cortex_web/live/senses_live.ex` — any town_square/book_id refs
- Modify: `lib/ex_cortex_web/live/guide_live.ex` — any old vocabulary in guide text
- Rename: `lib/ex_cortex_web/components/lodge_cards.ex` → `signal_cards.ex`, update module name
- Rename: `lib/ex_cortex_ui/components/charter_picker.ex` → `pathway_picker.ex`, update module name
- Modify: `lib/ex_cortex_web/live/quests_live.ex` — update event names (`create_quest` → `create_thought`, `toggle_quest_status` → `toggle_thought_status`, `delete_quest` → `delete_thought`)

**Step 1: Update LiveViews**
**Step 2: Update components**
**Step 3: Run tests**
**Step 4: Commit**

---

### Task 11: Remove legacy routes and delete legacy LiveViews

**Files:**
- Modify: `lib/ex_cortex_web/router.ex` — remove all legacy routes
- Delete: `lib/ex_cortex_web/live/lodge_live.ex` (if CortexLive covers it)
- Delete: `lib/ex_cortex_web/live/guild_hall_live.ex` (if NeuronsLive covers it)
- Delete: `lib/ex_cortex_web/live/grimoire_live.ex` (if ThoughtsLive covers it)
- Delete: `lib/ex_cortex_web/live/library_live.ex` (if MemoryLive covers it)
- Delete: `lib/ex_cortex_web/live/town_square_live.ex` (if SensesLive covers it)
- Delete: `lib/ex_cortex_web/live/quests_live.ex` (if ThoughtsLive covers it)

**Important:** Before deleting, verify the new LiveViews have equivalent functionality. If any legacy LiveView has features not yet in the new one, port them first.

**Step 1: Audit each legacy LiveView vs its replacement**
**Step 2: Port any missing features**
**Step 3: Remove legacy routes from router**
**Step 4: Delete legacy LiveView files**
**Step 5: Run tests**
**Step 6: Commit**

---

### Task 12: Update and rename test files

**Files:**
- Delete: `test/ex_cortex_web/live/lodge_live_test.exs`
- Delete: `test/ex_cortex_web/live/guild_hall_live_test.exs`
- Delete: `test/ex_cortex_web/live/grimoire_live_test.exs`
- Delete: `test/ex_cortex_web/live/library_live_test.exs`
- Delete: `test/ex_cortex_web/live/town_square_live_test.exs`
- Delete: `test/ex_cortex_web/live/quests_live_test.exs`
- Rename + update: `test/ex_cortex/lodge_test.exs` → `test/ex_cortex/signals_test.exs`
- Rename + update: `test/ex_cortex/guild_charters_test.exs` → `test/ex_cortex/cluster_pathways_test.exs`
- Rename + update: `test/ex_cortex/quest_runner_recording_test.exs` → `test/ex_cortex/thought_runner_recording_test.exs`
- Rename + update: `test/ex_cortex/step_runner_herald_test.exs` → `test/ex_cortex/impulse_runner_expression_test.exs`
- Rename + update: `test/ex_cortex/step_runner_lodge_card_test.exs` → `test/ex_cortex/impulse_runner_signal_test.exs`
- Rename + update: `test/ex_cortex/sources/lodge_watcher_test.exs` → `test/ex_cortex/sources/signal_watcher_test.exs`
- Rename + update: `test/ex_cortex_web/components/lodge_cards_test.exs` → `test/ex_cortex_web/components/signal_cards_test.exs`
- Rename + update: `test/ex_cortex/tools/query_lore_test.exs` → `test/ex_cortex/tools/query_memory_test.exs`
- Update: all remaining test files with old vocabulary (quest_debouncer_test, evaluator_test, etc.)
- Update: `test/ex_cortex/context_providers/member_roster_test.exs` — old vocab in test bodies
- Update: `test/ex_cortex/nextcloud/roles_test.exs` — `:manage_guilds` → `:manage_clusters`, `:run_quests` → `:run_thoughts`
- Update: `test/ex_cortex/obsidian/sync_test.exs` — `sync_lodge_card` → `sync_signal`, `sync_lore_entry` → `sync_engram`
- Update: `test/ex_cortex/integration/everyday_council_flow_test.exs` — all old vocab
- Update: any other test files with `_quest`, `lodge`, `guild`, `lore`, `herald`, `charter`, `member` references

**Step 1: Delete legacy LiveView test files**
**Step 2: Rename and update remaining test files**
**Step 3: Run full test suite**
**Step 4: Commit**

---

### Task 13: Update config and misc files

**Files:**
- Modify: `config/test.exs` — `head_render_path: "/guild-hall"` → `"/neurons"`
- Modify: `lib/ex_cortex/nextcloud/roles.ex` — `:manage_guilds` → `:manage_clusters`, `:run_quests` → `:run_thoughts`
- Modify: `lib/ex_cortex/llm/claude.ex` — `quest_id` → `thought_id` parameter names
- Modify: `priv/repo/seeds.local.exs.example` — any old vocabulary
- Modify: `lib/ex_cortex/app_telemetry.ex` — `quest` → `thought` references
- Modify: CLAUDE.md — remove legacy route mentions, update any stale references

**Step 1: Update all files**
**Step 2: Run tests**
**Step 3: Commit**

---

### Task 14: Fix test warnings

**Files:**
- Modify: `lib/ex_cortex/app_telemetry.ex` — handle `{:daydream_completed, _}` gracefully when DB is shutting down (wrap in try/rescue or check process state)
- Modify: `lib/ex_cortex/obsidian/sync.ex` — fix `DateTime.to_date/1` clause mismatch in signal card sync

**Step 1: Fix AppTelemetry**
**Step 2: Fix Obsidian.Sync**
**Step 3: Run tests, verify no warnings**
**Step 4: Commit**

---

### Task 15: Final verification and cleanup

**Step 1: Run full grep for old vocabulary**
```bash
grep -rn "guild\|grimoire\|lodge\|quest\|herald\|charter\|lore_\|book_id\|member_roster\|member_stats\|town.square\|ExCalibur\|ex_calibur" lib/ test/ config/ --include="*.ex" --include="*.exs" --include="*.yml" --include="*.toml" --include="*.sh"
```

**Step 2: Run full test suite**
```bash
mix test
```

**Step 3: Run format + credo**
```bash
mix format
mix credo
```

**Step 4: Final commit**

---
