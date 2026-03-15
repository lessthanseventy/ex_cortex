# Grimoire "Both" Mode + Charter Memory Quests — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `write_mode: "both"` and wire comprehensive memory/synthesis quests into all 8 guild charters, demonstrating every system capability in at least one charter.

**Architecture:** `write_mode: "both"` adds `log_title_template` and teaches `Lore.write_artifact/2` to write two entries per run. Each charter gets a memory quest using `output_type: "artifact"`, various write modes, and lore context providers on both verdict AND artifact quests — demonstrating the full feedback loop. Campaigns are updated to run memory synthesis as a final step.

**Capabilities to showcase across all 8 charters:**
- All trigger types: `scheduled`, `manual`, `source` (at least one each)
- Output types: `verdict` and `artifact`
- Write modes: `append`, `replace`, `both` (varied across charters)
- Context providers: `lore`, `static`, `quest_history`, `member_stats` (one each demonstrated)
- Campaign flows: `always`, `on_flag`, `on_pass`, memory synthesis as final step
- Roster strategies: solo apprentice, solo master, consensus all (all demonstrated)

**Tech Stack:** Ecto migrations, Phoenix LiveView, ExCortex.Lore, Excellence.Charters.*

---

## Task 1: write_mode "both" — Migration + Schema + Lore

**Files:**
- Create: `priv/repo/migrations/20260308300000_add_log_title_template_to_quests.exs`
- Modify: `lib/ex_cortex/quests/quest.ex`
- Modify: `lib/ex_cortex/lore.ex`
- Modify: `test/ex_cortex/lore_test.exs`

**Step 1: Write the migration**

```elixir
# priv/repo/migrations/20260308300000_add_log_title_template_to_quests.exs
defmodule ExCortex.Repo.Migrations.AddLogTitleTemplateToQuests do
  use Ecto.Migration

  def change do
    alter table(:excellence_quests) do
      add :log_title_template, :string
    end
  end
end
```

**Step 2: Run migration**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix ecto.migrate' --pane=main:1.3
```

Wait 15s. Expected: migration ran successfully.

**Step 3: Update Quest schema**

Replace `lib/ex_cortex/quests/quest.ex` with:

```elixir
defmodule ExCortex.Quests.Quest do
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
    :log_title_template
  ]

  def changeset(quest, attrs) do
    quest
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["active", "paused"])
    |> validate_inclusion(:trigger, ["manual", "source", "scheduled"])
    |> validate_inclusion(:output_type, ["verdict", "artifact"])
    |> validate_inclusion(:write_mode, ["append", "replace", "both"])
    |> unique_constraint(:name)
  end
end
```

**Step 4: Update Lore.write_artifact/2**

Replace `write_artifact/2` in `lib/ex_cortex/lore.ex` with:

```elixir
@doc """
Used by artifact quest runs. Appends or replaces based on quest write_mode.
  - "append": always creates a new entry
  - "replace": overwrites the existing quest-owned entry (never overwrites source: "manual")
  - "both": replaces the pinned summary entry AND appends a dated log entry
"""
def write_artifact(quest, attrs) do
  case quest.write_mode do
    "replace" ->
      replace_or_create(quest, attrs)

    "both" ->
      replace_or_create(quest, attrs)
      date = Calendar.strftime(Date.utc_today(), "%Y-%m-%d")
      log_template = quest.log_title_template || "#{quest.name || "Entry"} — Log — {date}"
      log_title = String.replace(log_template, "{date}", date)
      create_entry(Map.merge(attrs, %{quest_id: quest.id, title: log_title}))

    _ ->
      create_entry(Map.put(attrs, :quest_id, quest.id))
  end
end

defp replace_or_create(quest, attrs) do
  case Repo.one(
         from e in LoreEntry,
           where: e.quest_id == ^quest.id and e.source == "quest",
           limit: 1
       ) do
    nil -> create_entry(Map.put(attrs, :quest_id, quest.id))
    existing -> update_entry(existing, attrs)
  end
end
```

**Step 5: Add tests for "both" mode**

Add to `test/ex_cortex/lore_test.exs`:

```elixir
test "write_artifact both mode creates pinned summary and appends log" do
  quest = %{id: 10, write_mode: "both", name: "Test Quest", log_title_template: "Test Log — {date}"}
  {:ok, _} = Lore.write_artifact(quest, %{title: "Summary", source: "quest"})
  entries = Lore.list_entries(quest_id: 10)
  assert length(entries) == 2
  titles = Enum.map(entries, & &1.title)
  assert "Summary" in titles
  assert Enum.any?(titles, &String.starts_with?(&1, "Test Log"))
end

test "write_artifact both mode replaces summary but keeps appending log" do
  quest = %{id: 11, write_mode: "both", name: "Test Quest", log_title_template: "Log — {date}"}
  {:ok, _} = Lore.write_artifact(quest, %{title: "Summary", source: "quest"})
  {:ok, _} = Lore.write_artifact(quest, %{title: "Summary", source: "quest"})
  entries = Lore.list_entries(quest_id: 11)
  assert length(entries) == 3
end
```

**Step 6: Run lore tests**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/lore_test.exs 2>&1 | tail -10' --pane=main:1.3
```

Wait 30s. Expected: all tests pass.

**Step 7: Commit**

```bash
cd /home/andrew/projects/ex_cortex
git add priv/repo/migrations/20260308300000_add_log_title_template_to_quests.exs lib/ex_cortex/quests/quest.ex lib/ex_cortex/lore.ex test/ex_cortex/lore_test.exs
git commit -m "feat: write_mode 'both' — update pinned summary and append log"
```

---

## Task 2: Quest Form — "Both" write_mode UI

**Files:**
- Modify: `lib/ex_cortex_web/live/quests_live.ex`

**Step 1: Read the file**

Read the full `lib/ex_cortex_web/live/quests_live.ex`. Find the `write_mode` select in `new_quest_form` and `quest_card`, and how `write_mode`/`entry_title_template` are extracted in create/update handlers.

**Step 2: Add "both" option to write_mode selects**

In both `new_quest_form` and `quest_card`, add a third option to the write_mode select:

```heex
<option value="both" selected={@write_mode_preview == "both"}>Both (update summary + append log)</option>
```

If `write_mode_preview` tracking doesn't exist, add it like `output_previews` — initialized in `mount/3` from `q.write_mode`, updated in the change handler.

**Step 3: Show log_title_template when write_mode is "both"**

Inside the artifact fields section (where `entry_title_template` input already appears), add after it:

```heex
<%= if @write_mode_preview == "both" do %>
  <div>
    <label class="text-sm font-medium">Log title template</label>
    <input
      type="text"
      name="quest[log_title_template]"
      value={if assigns[:quest], do: (@quest.log_title_template || ""), else: ""}
      placeholder="Log — {date}"
      class="w-full h-9 text-sm border border-input rounded-md px-3 bg-background focus:outline-none focus:ring-1 focus:ring-ring"
    />
  </div>
<% end %>
```

**Step 4: Include log_title_template in create/update handlers**

In both create/update quest handlers, add:

```elixir
log_title_template = if output_type == "artifact", do: params["log_title_template"], else: nil
```

Add `log_title_template: log_title_template` to attrs.

**Step 5: Run tests**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex_web/live/quests_live_test.exs 2>&1 | tail -10' --pane=main:1.3
```

Wait 30s. Expected: 7 tests, 0 failures.

**Step 6: Commit**

```bash
git add lib/ex_cortex_web/live/quests_live.ex
git commit -m "feat: 'both' write mode option in quest form with log title template"
```

---

## Task 3: Charter Memory Quests + Full Capability Showcase

**Files:**
- Modify all 8 charter files in `/home/andrew/projects/ex_cellence/lib/excellence/charters/`

**Read this first:** Look at `lib/excellence/charters/accessibility_review.ex` to confirm the exact `quest_definitions/0` and `campaign_definitions/0` format before making changes to any file.

**Design principles applied per charter:**

| Charter | Memory write_mode | Scan context_provider | Source trigger | Campaign memory step |
|---|---|---|---|---|
| Accessibility | both | lore | — | ✓ |
| Code Review | both | lore | — | ✓ |
| Dependency Audit | both | lore | source (demo) | ✓ |
| Risk Assessment | replace | lore | — | ✓ |
| Content Moderation | both | static (demo) | — | ✓ |
| Incident Triage | append | quest_history (demo) | — | ✓ |
| Performance Audit | replace | lore | — | ✓ |
| Contract Review | both | member_stats (demo) | — | ✓ |

---

### Accessibility Review

**In `quest_definitions/0`:**

1. Update "WCAG Hourly Scan" to add lore context provider:
```elixir
%{
  name: "WCAG Hourly Scan",
  description: "Quick automated accessibility check by apprentice members",
  status: "active",
  trigger: "scheduled",
  schedule: "@hourly",
  roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  context_providers: [%{"type" => "lore", "tags" => ["a11y"], "limit" => 3, "sort" => "importance"}]
}
```

2. Add memory quest:
```elixir
%{
  name: "A11y Knowledge Synthesis",
  description: """
  Synthesize key accessibility findings into a knowledge entry. Identify what a future
  auditor should remember: chronic failures by component, WCAG criteria that keep
  surfacing, recently fixed patterns, and notable regressions. Be specific and
  actionable — "form labels are consistently missing" beats "some issues found".
  """,
  status: "active",
  trigger: "manual",
  schedule: nil,
  roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  output_type: "artifact",
  write_mode: "both",
  entry_title_template: "A11y Knowledge",
  log_title_template: "A11y Log — {date}",
  context_providers: [%{"type" => "lore", "tags" => ["a11y"], "limit" => 5, "sort" => "importance"}]
}
```

**In `campaign_definitions/0`:**

Update "Monthly Accessibility Review" to add memory synthesis as final step:
```elixir
%{
  name: "Monthly Accessibility Review",
  description: "Automated scan that escalates to full audit on any findings, then synthesizes knowledge",
  status: "active",
  trigger: "scheduled",
  schedule: "@monthly",
  steps: [
    %{"quest_name" => "WCAG Hourly Scan", "flow" => "always"},
    %{"quest_name" => "Full Accessibility Audit", "flow" => "on_flag"},
    %{"quest_name" => "A11y Knowledge Synthesis", "flow" => "always"}
  ],
  source_ids: []
}
```

---

### Code Review

**In `quest_definitions/0`:**

1. Update "Code Quality Scan" to add lore context:
```elixir
%{
  name: "Code Quality Scan",
  description: "Quick automated code quality check by apprentice members",
  status: "active",
  trigger: "scheduled",
  schedule: "@hourly",
  roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  context_providers: [%{"type" => "lore", "tags" => ["code-review"], "limit" => 3, "sort" => "importance"}]
}
```

2. Add memory quest:
```elixir
%{
  name: "Code Pattern Memory",
  description: """
  Synthesize recurring code quality findings into institutional memory. Document:
  security anti-patterns that keep appearing, architectural debt items identified,
  modules or areas with consistent issues, and recently resolved patterns that
  improved the codebase. Focus on what would help a reviewer calibrate expectations
  for this specific codebase.
  """,
  status: "active",
  trigger: "manual",
  schedule: nil,
  roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  output_type: "artifact",
  write_mode: "both",
  entry_title_template: "Code Patterns",
  log_title_template: "Code Review Log — {date}",
  context_providers: [%{"type" => "lore", "tags" => ["code-review"], "limit" => 5, "sort" => "importance"}]
}
```

**In `campaign_definitions/0`:** Add `%{"quest_name" => "Code Pattern Memory", "flow" => "always"}` as the final step.

---

### Dependency Audit

Demonstrates `trigger: "source"` on the scan quest (hook up a git source to watch deps files).

**In `quest_definitions/0`:**

1. Update "Dependency Quick Scan" to use source trigger and lore context:
```elixir
%{
  name: "Dependency Quick Scan",
  description: "Automated dependency scan triggered when dependency files change",
  status: "active",
  trigger: "source",
  schedule: nil,
  roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  context_providers: [%{"type" => "lore", "tags" => ["deps"], "limit" => 5, "sort" => "importance"}]
}
```

2. Add memory quest:
```elixir
%{
  name: "Dependency Risk Register",
  description: """
  Synthesize the current dependency risk landscape into a living register. Include:
  known vulnerable packages with CVE references, license exceptions approved,
  packages flagged for replacement with migration notes, and supply chain concerns.
  This entry is the single source of truth for dependency health.
  """,
  status: "active",
  trigger: "manual",
  schedule: nil,
  roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  output_type: "artifact",
  write_mode: "both",
  entry_title_template: "Dependency Risk Register",
  log_title_template: "Dependency Audit Log — {date}",
  context_providers: [%{"type" => "lore", "tags" => ["deps"], "limit" => 5, "sort" => "importance"}]
}
```

**In `campaign_definitions/0`:** Add memory quest as final step to "Weekly Dependency Audit Campaign".

---

### Risk Assessment

Demonstrates `write_mode: "replace"` — the risk picture is current state, not a log.

**In `quest_definitions/0`:**

1. Update "Risk Quick Scan" to add lore context:
```elixir
%{
  name: "Risk Quick Scan",
  description: "Quick automated risk scan by apprentice members",
  status: "active",
  trigger: "scheduled",
  schedule: "@hourly",
  roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  context_providers: [%{"type" => "lore", "tags" => ["risk"], "limit" => 3, "sort" => "importance"}]
}
```

2. Add memory quest (write_mode: "replace" — always shows current picture):
```elixir
%{
  name: "Risk Pattern Memory",
  description: """
  Synthesize current risk patterns and fraud signals into a single up-to-date entry.
  Include: active high-risk patterns seen recently, confirmed fraud signals,
  risk score calibration notes (what scored high but was fine, what scored low but
  was problematic), and any resolved compliance edge cases. Replace the previous
  entry — this should always reflect the current threat landscape.
  """,
  status: "active",
  trigger: "manual",
  schedule: nil,
  roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  output_type: "artifact",
  write_mode: "replace",
  entry_title_template: "Risk Patterns — Current",
  log_title_template: nil,
  context_providers: [%{"type" => "lore", "tags" => ["risk"], "limit" => 5, "sort" => "importance"}]
}
```

**In `campaign_definitions/0`:** Add memory quest as final step to "Risk Assessment Campaign".

---

### Content Moderation

Demonstrates `context_providers: static` on the scan quest — inject your community standards document so members always review against them.

**In `quest_definitions/0`:**

1. Update "Content Safety Scan" to add static context:
```elixir
%{
  name: "Content Safety Scan",
  description: "Quick automated content safety check by apprentice members",
  status: "active",
  trigger: "scheduled",
  schedule: "@hourly",
  roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  context_providers: [
    %{"type" => "static", "text" => "Community standards: maintain respectful discourse. Hate speech, harassment, and graphic violence are not permitted. Gray areas should be escalated."},
    %{"type" => "lore", "tags" => ["moderation"], "limit" => 3, "sort" => "newest"}
  ]
}
```

2. Add memory quest:
```elixir
%{
  name: "Moderation Edge Case Log",
  description: """
  Synthesize moderation decisions on edge cases into institutional memory. Document:
  gray-area content types and how they were ruled, evolving community standards applied,
  escalation decisions and their outcomes, and any inconsistencies noted across reviewers.
  This helps the guild stay consistent over time.
  """,
  status: "active",
  trigger: "manual",
  schedule: nil,
  roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  output_type: "artifact",
  write_mode: "both",
  entry_title_template: "Moderation Patterns",
  log_title_template: "Moderation Log — {date}",
  context_providers: [%{"type" => "lore", "tags" => ["moderation"], "limit" => 5, "sort" => "newest"}]
}
```

**In `campaign_definitions/0`:** Add memory quest as final step to "Continuous Moderation Campaign".

---

### Incident Triage

Demonstrates `write_mode: "append"` (pure history is the point) and `context_providers: quest_history` on the scan quest (past triage decisions as context).

**In `quest_definitions/0`:**

1. Update "Incident Quick Triage" to add quest_history context:
```elixir
%{
  name: "Incident Quick Triage",
  description: "Quick automated incident severity assessment by apprentice members",
  status: "active",
  trigger: "scheduled",
  schedule: "@hourly",
  roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  context_providers: [
    %{"type" => "quest_history", "limit" => 5},
    %{"type" => "lore", "tags" => ["incidents"], "limit" => 3, "sort" => "newest"}
  ]
}
```

2. Add memory quest (write_mode: "append" — you want full incident history):
```elixir
%{
  name: "Incident Pattern Memory",
  description: """
  Synthesize incident patterns and response learnings into the incident log.
  Document: the incident type, root cause, severity, response taken, and what
  was learned. This entry is appended each time — the accumulated history is what
  gives future triagers context to make faster, better-calibrated decisions.
  """,
  status: "active",
  trigger: "manual",
  schedule: nil,
  roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  output_type: "artifact",
  write_mode: "append",
  entry_title_template: "Incident Report — {date}",
  log_title_template: nil,
  context_providers: [%{"type" => "lore", "tags" => ["incidents"], "limit" => 10, "sort" => "newest"}]
}
```

**In `campaign_definitions/0`:** Add memory quest as final step to "Incident Response Campaign".

---

### Performance Audit

Demonstrates `write_mode: "replace"` for baselines — the current baseline is what matters.

**In `quest_definitions/0`:**

1. Update "Performance Quick Scan" to add lore context:
```elixir
%{
  name: "Performance Quick Scan",
  description: "Quick automated performance analysis by apprentice members",
  status: "active",
  trigger: "scheduled",
  schedule: "@hourly",
  roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  context_providers: [%{"type" => "lore", "tags" => ["performance"], "limit" => 3, "sort" => "importance"}]
}
```

2. Add memory quest (write_mode: "replace" — baseline should always be current):
```elixir
%{
  name: "Performance Baseline Memory",
  description: """
  Synthesize performance findings into a current baseline entry. Document:
  key metrics for hot paths, known bottlenecks with context (severity, when found,
  whether being addressed), optimization wins already applied (so they are not
  re-recommended), and regressions detected with probable causes. Always replace
  the previous entry — this represents current system performance reality.
  """,
  status: "active",
  trigger: "manual",
  schedule: nil,
  roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  output_type: "artifact",
  write_mode: "replace",
  entry_title_template: "Performance Baselines — Current",
  log_title_template: nil,
  context_providers: [%{"type" => "lore", "tags" => ["performance"], "limit" => 5, "sort" => "importance"}]
}
```

**In `campaign_definitions/0`:** Add memory quest as final step to "Performance Audit Campaign".

---

### Contract Review

Demonstrates `context_providers: member_stats` on scan quest — members can see who's flagged the most issues to calibrate their confidence.

**In `quest_definitions/0`:**

1. Update "Contract Risk Scan" to add member_stats + lore context:
```elixir
%{
  name: "Contract Risk Scan",
  description: "Quick automated contract risk analysis by apprentice members",
  status: "active",
  trigger: "scheduled",
  schedule: "@hourly",
  roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  context_providers: [
    %{"type" => "member_stats"},
    %{"type" => "lore", "tags" => ["contracts"], "limit" => 3, "sort" => "importance"}
  ]
}
```

2. Add memory quest:
```elixir
%{
  name: "Contract Knowledge Memory",
  description: """
  Synthesize contract review learnings into institutional memory. Document:
  standard clauses that routinely get flagged and the standing reasoning,
  known risky vendors and why, obligation items being actively tracked,
  and ambiguity patterns that have caused issues in the past. This entry gives
  every new contract review the benefit of institutional experience.
  """,
  status: "active",
  trigger: "manual",
  schedule: nil,
  roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
  source_ids: [],
  output_type: "artifact",
  write_mode: "both",
  entry_title_template: "Contract Knowledge",
  log_title_template: "Contract Review Log — {date}",
  context_providers: [%{"type" => "lore", "tags" => ["contracts"], "limit" => 5, "sort" => "importance"}]
}
```

**In `campaign_definitions/0`:** Add memory quest as final step to "Contract Review Campaign".

---

### After all 8 charters are updated:

**Step: Verify ex_cellence compiles**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cellence && mix compile 2>&1 | tail -10' --pane=main:1.3
```

Wait 30s. Expected: no errors.

**Step: Verify ex_cortex compiles**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_cortex && mix compile 2>&1 | tail -10' --pane=main:1.3
```

Wait 30s. Expected: no errors.

**Step: Commit charters from ex_cellence directory**

```bash
cd /home/andrew/projects/ex_cellence
git add lib/excellence/charters/
git commit -m "feat: memory synthesis quests in all 8 charters — full Grimoire capability showcase"
```

---

## Notes

- The 6 pre-existing test failures in `mix test` are not related to this feature — do not try to fix them
- Charter quest_definitions use atom keys (`:output_type`, `:write_mode`, etc.) — Ecto cast handles them
- `source_ids: []` on the Dependency Quick Scan is correct — user attaches actual sources via Stacks after install; the `trigger: "source"` shows intent
- Memory quests are `trigger: "manual"` and also appear as campaign final steps — they can be run standalone or as part of the campaign
- Each charter's scan/verdict quests now read lore as context, creating the full feedback loop: scroll → scan (with lore context) → memory synthesis → next scan (with richer context)
- `log_title_template: nil` on pure-replace and pure-append quests is fine — the field is optional
