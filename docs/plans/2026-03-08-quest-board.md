# Quest Board Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Quest Board page (`/quest-board`) where users browse pre-configured campaign templates by category, see which ones they can run today (based on configured sources/heralds/members), and install campaigns with one click — without replacing their existing guild.

**Architecture:** `ExCalibur.Board` module holds all campaign templates as plain data structs with requirements declarations. A new LiveView loads templates, checks requirements against live DB state at mount, and installs quest+campaign records on demand. `preferred_who` in QuestRunner allows templates to route to named members when present, falling back to rank-based routing.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto, SaladUI badges/buttons, existing `Quests.create_quest/1` and `Quests.create_campaign/1` helpers

---

## Key Concepts

### Board.Template struct
```elixir
%ExCalibur.Board.Template{
  id: "jira_ticket_triage",         # unique atom-like string
  name: "Jira Ticket Triage",
  category: :triage,                 # :triage | :reporting | :generation | :review | :onboarding
  description: "...",
  suggested_team: "Advisory text about what team works well",
  requires: [                        # hard requirements — must be met to install
    {:source_type, "jira"},          # active Source with source_type == "jira"
    {:herald_type, "slack"},         # any Herald with type == "slack"
    # :any_members                   # at least one active Member
  ],
  quest_definitions: [...],          # same shape as charter quest_definitions
  campaign_definition: %{...}        # same shape as charter campaign_definitions entry
}
```

### Requirements checking
- `{:source_type, type}` → `Repo.exists?(from s in Source, where: s.source_type == ^type and s.status in ["active", "paused"])`
- `{:herald_type, type}` → `Repo.exists?(from h in Herald, where: h.type == ^type)`
- `:any_members` → `Repo.exists?(from m in Member, where: m.type == "role" and m.status == "active")`

Returns list of `{met :: boolean, label :: String.t}` tuples.

### preferred_who in QuestRunner
Roster entries can have `"preferred_who" => "member-name"`. QuestRunner tries to find a member by that name first; if none found, falls back to `"who"` field (rank/all/etc).

```elixir
# roster step example
%{"who" => "master", "preferred_who" => "impact-assessor", "when" => "on_trigger", "how" => "solo"}
```

### Installation (additive, not replace)
Unlike Guild Hall which wipes everything, Quest Board is additive: creates new quests and a campaign. User may already have a guild installed. No deletions.

---

## Task 1: Jira Book

**Files:**
- Modify: `lib/ex_calibur/sources/book.ex` (inside `books/0`, after the Dependency Audit section, before Sandbox-enabled books)

**Step 1: Add the Jira book entry**

Add this entry to the `books/0` list in `lib/ex_calibur/sources/book.ex`, in the dedicated section for Incident Triage (or create a new Jira section after the Dependency Audit entries at line ~164):

```elixir
# Jira
%__MODULE__{
  id: "jira_webhook",
  name: "Jira Webhook",
  description:
    "Receive Jira issue events via webhook — new issues, status changes, priority escalations.",
  source_type: "webhook",
  default_config: %{},
  suggested_guild: "Incident Triage",
  kind: :book
},
%__MODULE__{
  id: "jira_feed",
  name: "Jira Activity Feed",
  description: "Poll a Jira board activity feed for new and updated issues.",
  source_type: "feed",
  default_config: %{"url" => "", "interval" => 300_000},
  suggested_guild: nil,
  kind: :book
},
```

**Step 2: Verify no test failures**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur/sources/' --pane=main:1.3`
Expected: All pass (these are pure data, no tests needed)

**Step 3: Commit**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && git add lib/ex_calibur/sources/book.ex && git commit -m "feat: add Jira webhook and feed books to Library"' --pane=main:1.3
```

---

## Task 2: preferred_who in QuestRunner

**Files:**
- Modify: `lib/ex_calibur/quest_runner.ex` (resolve_members section, lines ~100-139)

**Step 1: Add `resolve_members` clause for preferred_who**

In `resolve_members/1`, the caller passes the `step` map (currently it extracts `step["who"]`). We need to change the call site to pass the whole step and add preferred_who logic.

The change is in two places:

**Change 1** — in `run/2` for roster list (line 73), change:
```elixir
members = resolve_members(step["who"])
```
to:
```elixir
members = resolve_members(step)
```

**Change 2** — in `run_artifact/2` (line 276), change:
```elixir
[first | _] -> resolve_members(first["who"])
```
to:
```elixir
[first | _] -> resolve_members(first)
```

**Change 3** — rename all `resolve_members(who)` private function clauses to accept a step map, and add `preferred_who` dispatch at the top:

```elixir
# New dispatcher — resolves preferred_who or falls back to who
defp resolve_members(%{"preferred_who" => name} = step) when is_binary(name) and name != "" do
  case from(m in Member,
         where: m.type == "role" and m.status == "active" and m.name == ^name
       )
       |> Repo.all()
       |> Enum.map(&member_to_runner_spec/1) do
    [] -> resolve_members(%{step | "preferred_who" => nil})
    members -> members
  end
end

defp resolve_members(%{"who" => who}), do: resolve_members(who)
defp resolve_members(step) when is_map(step), do: resolve_members(Map.get(step, "who", "all"))

# All the existing clauses stay exactly the same, taking a string:
defp resolve_members("all") do ... end
defp resolve_members("apprentice"), do: resolve_by_rank("apprentice")
# ... etc
```

**Step 2: Run existing QuestRunner tests**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur/quest_runner_test.exs' --pane=main:1.3`

If the file doesn't exist, skip to step 3 (no existing tests to break).

**Step 3: Compile check**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix compile --warnings-as-errors 2>&1 | head -30' --pane=main:1.3`
Expected: No warnings or errors

**Step 4: Commit**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && git add lib/ex_calibur/quest_runner.ex && git commit -m "feat: preferred_who roster field with member name fallback in QuestRunner"' --pane=main:1.3
```

---

## Task 3: ExCalibur.Board module (core)

**Files:**
- Create: `lib/ex_calibur/board.ex`

**Step 1: Create the Board module**

```elixir
defmodule ExCalibur.Board do
  @moduledoc """
  Pre-configured campaign templates for the Quest Board.

  Templates are organized by category and declare hard requirements
  (source types and herald types that must be configured) so the UI
  can show which campaigns are ready to install today.
  """

  import Ecto.Query

  alias ExCalibur.Heralds.Herald
  alias ExCalibur.Repo
  alias ExCalibur.Sources.Source
  alias Excellence.Schemas.Member

  defstruct [
    :id,
    :name,
    :category,
    :description,
    :suggested_team,
    :requires,
    :quest_definitions,
    :campaign_definition
  ]

  @categories [:triage, :reporting, :generation, :review, :onboarding]

  def categories, do: @categories

  def all do
    triage() ++ reporting() ++ generation() ++ review() ++ onboarding()
  end

  def by_category(cat), do: Enum.filter(all(), &(&1.category == cat))

  def get(id), do: Enum.find(all(), &(&1.id == id))

  @doc """
  Check which requirements are met for a template.
  Returns list of {met :: boolean, label :: String.t} tuples.
  """
  def check_requirements(%__MODULE__{requires: requires}) do
    Enum.map(requires, fn
      {:source_type, type} ->
        met =
          Repo.exists?(
            from(s in Source,
              where: s.source_type == ^type and s.status in ["active", "paused"]
            )
          )

        {met, "#{humanize(type)} source"}

      {:herald_type, type} ->
        met = Repo.exists?(from(h in Herald, where: h.type == ^type))
        {met, "#{humanize(type)} herald"}

      :any_members ->
        met =
          Repo.exists?(from(m in Member, where: m.type == "role" and m.status == "active"))

        {met, "Active members"}
    end)
  end

  @doc """
  Returns :ready | :almost | :unavailable based on requirements.
  :ready — all met
  :almost — only one missing
  :unavailable — two or more missing
  """
  def readiness(%__MODULE__{requires: []} = _template), do: :ready

  def readiness(template) do
    results = check_requirements(template)
    missing = Enum.count(results, fn {met, _} -> !met end)

    cond do
      missing == 0 -> :ready
      missing == 1 -> :almost
      true -> :unavailable
    end
  end

  @doc """
  Install a template: creates its quests and campaign.
  Returns {:ok, campaign} or {:error, reason}.
  """
  def install(%__MODULE__{} = template) do
    Enum.each(template.quest_definitions, fn attrs ->
      ExCalibur.Quests.create_quest(attrs)
    end)

    quest_by_name = Map.new(ExCalibur.Quests.list_quests(), &{&1.name, &1.id})

    steps =
      Enum.map(template.campaign_definition.steps, fn step ->
        %{"quest_id" => Map.get(quest_by_name, step["quest_name"]), "flow" => step["flow"]}
      end)

    ExCalibur.Quests.create_campaign(Map.put(template.campaign_definition, :steps, steps))
  end

  defp humanize(str), do: str |> String.replace("_", " ") |> String.capitalize()

  # ---------------------------------------------------------------------------
  # Template definitions — loaded by all/0
  # ---------------------------------------------------------------------------

  defp triage, do: ExCalibur.Board.Triage.templates()
  defp reporting, do: ExCalibur.Board.Reporting.templates()
  defp generation, do: ExCalibur.Board.Generation.templates()
  defp review, do: ExCalibur.Board.Review.templates()
  defp onboarding, do: ExCalibur.Board.Onboarding.templates()
end
```

**Step 2: Compile check**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix compile 2>&1 | head -20' --pane=main:1.3`
Expected: Compile errors for missing submodules (expected — will add them in tasks 4-8)

**Step 3: Commit**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && git add lib/ex_calibur/board.ex && git commit -m "feat: ExCalibur.Board core module with requirements checking and install"' --pane=main:1.3
```

---

## Task 4: Board Templates — Triage

**Files:**
- Create: `lib/ex_calibur/board/triage.ex`

**Step 1: Create the triage templates file**

```elixir
defmodule ExCalibur.Board.Triage do
  @moduledoc "Source-triggered triage campaign templates."

  alias ExCalibur.Board

  def templates do
    [
      jira_ticket_triage(),
      github_issue_triage(),
      error_monitor(),
      feed_threat_triage()
    ]
  end

  defp jira_ticket_triage do
    %Board{
      id: "jira_ticket_triage",
      name: "Jira Ticket Triage",
      category: :triage,
      description:
        "Automatically triage incoming Jira tickets by severity, route urgent ones for full review, and post a Slack summary. Runs whenever new ticket data arrives.",
      suggested_team:
        "Works with any guild. The Incident Triage guild (ImpactAssessor + RootCauseAnalyst + EscalationRouter) is a natural fit.",
      requires: [
        {:source_type, "webhook"},
        {:herald_type, "slack"}
      ],
      quest_definitions: [
        %{
          name: "Jira Quick Triage",
          description:
            "Quick triage of incoming Jira ticket — assess urgency and route for full review if warranted.",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [
            %{
              "who" => "apprentice",
              "preferred_who" => "impact-assessor",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: []
        },
        %{
          name: "Jira Full Assessment",
          description:
            "Full consensus assessment of a Jira ticket — severity, root cause, and recommended response.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{"who" => "all", "when" => "on_trigger", "how" => "consensus"}
          ],
          source_ids: []
        },
        %{
          name: "Jira Slack Alert",
          description:
            "Post a concise Jira ticket summary and recommended action to the team Slack channel.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{
              "who" => "master",
              "preferred_who" => "escalation-router",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "slack",
          herald_name: "slack:default"
        }
      ],
      campaign_definition: %{
        name: "Jira Ticket Triage Campaign",
        description: "Source-triggered triage that escalates high-severity Jira tickets to Slack.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "Jira Quick Triage", "flow" => "always"},
          %{"quest_name" => "Jira Full Assessment", "flow" => "on_flag"},
          %{"quest_name" => "Jira Slack Alert", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp github_issue_triage do
    %Board{
      id: "github_issue_triage",
      name: "GitHub Issue Triage",
      category: :triage,
      description:
        "Triage incoming GitHub issues via webhook — assess severity and file a tracked issue response for confirmed bugs or blockers.",
      suggested_team:
        "Code Review guild works well. Any guild with code-aware members will do.",
      requires: [
        {:source_type, "webhook"},
        {:herald_type, "github_issue"}
      ],
      quest_definitions: [
        %{
          name: "GitHub Issue Quick Scan",
          description:
            "Quick triage of a GitHub issue — is it a confirmed bug, feature request, or noise?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
          source_ids: []
        },
        %{
          name: "GitHub Issue Full Review",
          description: "Full consensus review of a GitHub issue — priority, label suggestions, and response.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "File GitHub Issue Response",
          description: "File a tracked GitHub issue with assessment and recommended action.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "github_issue",
          herald_name: "github_issue:default"
        }
      ],
      campaign_definition: %{
        name: "GitHub Issue Triage Campaign",
        description: "Webhook-triggered triage that files tracked responses for confirmed bugs.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "GitHub Issue Quick Scan", "flow" => "always"},
          %{"quest_name" => "GitHub Issue Full Review", "flow" => "on_flag"},
          %{"quest_name" => "File GitHub Issue Response", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp error_monitor do
    %Board{
      id: "error_monitor",
      name: "Error Monitor & Page",
      category: :triage,
      description:
        "Stream errors from a log aggregator or error tracker, triage severity, and page on-call for critical incidents.",
      suggested_team:
        "Incident Triage guild (ImpactAssessor + RootCauseAnalyst + EscalationRouter) is the ideal fit.",
      requires: [
        {:source_type, "websocket"},
        {:herald_type, "pagerduty"}
      ],
      quest_definitions: [
        %{
          name: "Error Stream Quick Scan",
          description: "Quick scan of incoming error stream data — is this page-worthy?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [
            %{
              "who" => "apprentice",
              "preferred_who" => "impact-assessor",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: []
        },
        %{
          name: "Error Full Triage",
          description: "Full incident triage — severity, root cause, and page decision.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Page On-Call Engineer",
          description: "Page on-call via PagerDuty when the error warrants immediate response.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{
              "who" => "master",
              "preferred_who" => "escalation-router",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "pagerduty",
          herald_name: "pagerduty:default"
        }
      ],
      campaign_definition: %{
        name: "Error Monitor Campaign",
        description: "Real-time error stream triage with PagerDuty escalation for critical issues.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "Error Stream Quick Scan", "flow" => "always"},
          %{"quest_name" => "Error Full Triage", "flow" => "on_flag"},
          %{"quest_name" => "Page On-Call Engineer", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp feed_threat_triage do
    %Board{
      id: "feed_threat_triage",
      name: "Threat Feed Monitor",
      category: :triage,
      description:
        "Monitor industry threat intelligence feeds for signals relevant to your stack. Escalates findings to Slack.",
      suggested_team:
        "Risk Assessment guild (RiskScorer + ComplianceChecker + FraudDetector) is ideal.",
      requires: [
        {:source_type, "feed"},
        {:herald_type, "slack"}
      ],
      quest_definitions: [
        %{
          name: "Threat Feed Quick Scan",
          description: "Quick scan of incoming threat feed entries — is this relevant to our stack?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
          source_ids: []
        },
        %{
          name: "Threat Full Assessment",
          description: "Full consensus assessment of threat signal — risk level and recommended response.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Post Threat Alert",
          description: "Post threat assessment and recommended action to team Slack channel.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "slack",
          herald_name: "slack:default"
        }
      ],
      campaign_definition: %{
        name: "Threat Feed Monitor Campaign",
        description: "Feed-triggered threat intelligence triage with Slack escalation.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "Threat Feed Quick Scan", "flow" => "always"},
          %{"quest_name" => "Threat Full Assessment", "flow" => "on_flag"},
          %{"quest_name" => "Post Threat Alert", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end
end
```

**Step 2: Compile check**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix compile 2>&1 | grep -E "error|warning" | head -20' --pane=main:1.3`

**Step 3: Commit**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && git add lib/ex_calibur/board/triage.ex && git commit -m "feat: Quest Board triage templates (Jira, GitHub issue, error monitor, threat feed)"' --pane=main:1.3
```

---

## Task 5: Board Templates — Reporting

**Files:**
- Create: `lib/ex_calibur/board/reporting.ex`

**Step 1: Create the reporting templates file**

```elixir
defmodule ExCalibur.Board.Reporting do
  @moduledoc "Scheduled reporting and digest campaign templates."

  alias ExCalibur.Board

  def templates do
    [
      weekly_security_digest(),
      daily_standup_report(),
      sprint_code_quality_summary(),
      monthly_risk_summary()
    ]
  end

  defp weekly_security_digest do
    %Board{
      id: "weekly_security_digest",
      name: "Weekly Security Digest",
      category: :reporting,
      description:
        "Synthesize security signals from the past week into a concise digest. Covers CVEs, threat intelligence, and risk patterns. Posted to Slack every week.",
      suggested_team:
        "Risk Assessment or Dependency Audit guild. Any security-aware members will do.",
      requires: [
        {:source_type, "feed"},
        {:herald_type, "slack"}
      ],
      quest_definitions: [
        %{
          name: "Weekly Security Synthesis",
          description: """
          Synthesize the past week's security signals into a structured digest. Include:
          - Top CVEs and their relevance to our stack
          - Emerging threat patterns
          - Dependency advisories to action
          - One recommended action for the team
          Keep it scannable — bullet points over prose.
          """,
          status: "active",
          trigger: "scheduled",
          schedule: "@weekly",
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Security Digest — {date}",
          log_title_template: nil,
          context_providers: [
            %{"type" => "quest_history", "limit" => 10},
            %{"type" => "lore", "tags" => ["security", "deps", "risk"], "limit" => 10, "sort" => "newest"}
          ]
        },
        %{
          name: "Post Security Digest",
          description: "Post the weekly security digest to the team Slack channel.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "slack",
          herald_name: "slack:default"
        }
      ],
      campaign_definition: %{
        name: "Weekly Security Digest Campaign",
        description: "Weekly security synthesis posted to Slack every Monday.",
        status: "active",
        trigger: "scheduled",
        schedule: "@weekly",
        steps: [
          %{"quest_name" => "Weekly Security Synthesis", "flow" => "always"},
          %{"quest_name" => "Post Security Digest", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp daily_standup_report do
    %Board{
      id: "daily_standup_report",
      name: "Daily AI Standup",
      category: :reporting,
      description:
        "Every morning, synthesize yesterday's guild activity into a concise standup: what ran, what flagged, what needs attention. Posted to Slack.",
      suggested_team: "Works with any guild — reads from quest history.",
      requires: [
        {:herald_type, "slack"},
        :any_members
      ],
      quest_definitions: [
        %{
          name: "Daily Standup Synthesis",
          description: """
          Synthesize yesterday's guild activity into a daily standup format:
          - What quests ran and their outcomes
          - Any flags or escalations that need human attention
          - Patterns or anomalies worth noting
          - Suggested focus for today
          Be concise — this is a morning briefing, not a report.
          """,
          status: "active",
          trigger: "scheduled",
          schedule: "0 8 * * *",
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Standup — {date}",
          log_title_template: nil,
          context_providers: [
            %{"type" => "quest_history", "limit" => 20}
          ]
        },
        %{
          name: "Post Daily Standup",
          description: "Post the daily standup briefing to team Slack.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "slack",
          herald_name: "slack:default"
        }
      ],
      campaign_definition: %{
        name: "Daily AI Standup Campaign",
        description: "Daily 8am standup synthesis from quest history, posted to Slack.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 8 * * *",
        steps: [
          %{"quest_name" => "Daily Standup Synthesis", "flow" => "always"},
          %{"quest_name" => "Post Daily Standup", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp sprint_code_quality_summary do
    %Board{
      id: "sprint_code_quality_summary",
      name: "Sprint Code Quality Report",
      category: :reporting,
      description:
        "At the end of each sprint, synthesize code quality findings from the week's commits into a team report with trends and action items.",
      suggested_team:
        "Code Review guild. Works with any code-aware members.",
      requires: [
        {:source_type, "git"},
        {:herald_type, "slack"}
      ],
      quest_definitions: [
        %{
          name: "Sprint Quality Synthesis",
          description: """
          Synthesize this sprint's code quality findings into a team report. Include:
          - Overall quality trend (improving/stable/declining)
          - Most common issues flagged and their frequency
          - Files or areas with recurring problems
          - Wins — things that improved or were fixed
          - 2-3 concrete action items for next sprint
          """,
          status: "active",
          trigger: "scheduled",
          schedule: "@weekly",
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Sprint Quality Report — {date}",
          log_title_template: nil,
          context_providers: [
            %{"type" => "quest_history", "limit" => 30},
            %{"type" => "lore", "tags" => ["code-quality", "performance"], "limit" => 5, "sort" => "newest"}
          ]
        },
        %{
          name: "Post Sprint Quality Report",
          description: "Post the sprint quality report to the team Slack channel.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "slack",
          herald_name: "slack:default"
        }
      ],
      campaign_definition: %{
        name: "Sprint Code Quality Campaign",
        description: "Weekly sprint quality synthesis posted to Slack.",
        status: "active",
        trigger: "scheduled",
        schedule: "@weekly",
        steps: [
          %{"quest_name" => "Sprint Quality Synthesis", "flow" => "always"},
          %{"quest_name" => "Post Sprint Quality Report", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp monthly_risk_summary do
    %Board{
      id: "monthly_risk_summary",
      name: "Monthly Risk Executive Summary",
      category: :reporting,
      description:
        "Monthly executive-level risk and compliance roll-up. Aggregates risk assessments, compliance flags, and dependency health into a summary emailed to stakeholders.",
      suggested_team:
        "Risk Assessment guild. Compliance-aware members work well.",
      requires: [
        {:herald_type, "email"}
      ],
      quest_definitions: [
        %{
          name: "Monthly Risk Synthesis",
          description: """
          Synthesize this month's risk and compliance posture into an executive summary. Include:
          - Overall risk trend and current rating
          - Top 3 risks by severity with status
          - Compliance findings and remediation status
          - Dependency health snapshot
          - Recommended executive actions
          Write for a non-technical audience.
          """,
          status: "active",
          trigger: "scheduled",
          schedule: "0 9 1 * *",
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Monthly Risk Summary — {date}",
          log_title_template: nil,
          context_providers: [
            %{"type" => "quest_history", "limit" => 50},
            %{"type" => "lore", "tags" => ["risk", "compliance", "deps"], "limit" => 10, "sort" => "importance"}
          ]
        },
        %{
          name: "Email Monthly Risk Summary",
          description: "Email the monthly risk summary to stakeholders.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "email",
          herald_name: "email:default"
        }
      ],
      campaign_definition: %{
        name: "Monthly Risk Summary Campaign",
        description: "First-of-month executive risk summary emailed to stakeholders.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 9 1 * *",
        steps: [
          %{"quest_name" => "Monthly Risk Synthesis", "flow" => "always"},
          %{"quest_name" => "Email Monthly Risk Summary", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end
end
```

**Step 2: Compile + commit**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix compile 2>&1 | grep error | head -10 && git add lib/ex_calibur/board/reporting.ex && git commit -m "feat: Quest Board reporting templates (security digest, standup, code quality, risk summary)"' --pane=main:1.3
```

---

## Task 6: Board Templates — Generation

**Files:**
- Create: `lib/ex_calibur/board/generation.ex`

**Step 1: Create the generation templates file**

```elixir
defmodule ExCalibur.Board.Generation do
  @moduledoc "On-demand artifact generation campaign templates."

  alias ExCalibur.Board

  def templates do
    [
      incident_postmortem(),
      release_notes(),
      threat_model_report(),
      onboarding_brief()
    ]
  end

  defp incident_postmortem do
    %Board{
      id: "incident_postmortem",
      name: "Incident Postmortem",
      category: :generation,
      description:
        "On-demand structured postmortem document from incident history and triage logs. Each run appends a new postmortem entry to the incident log.",
      suggested_team:
        "Incident Triage guild. Any members with system analysis capability work.",
      requires: [],
      quest_definitions: [
        %{
          name: "Write Incident Postmortem",
          description: """
          Write a structured incident postmortem. Cover:
          - Incident timeline (detection → response → resolution)
          - Root cause analysis (immediate and contributing causes)
          - Impact (users affected, duration, severity)
          - What went well
          - What went wrong
          - Action items with owners and deadlines
          Use the 5 Whys where helpful.
          """,
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Postmortem — {date}",
          log_title_template: nil,
          context_providers: [
            %{"type" => "quest_history", "limit" => 10},
            %{"type" => "lore", "tags" => ["incidents"], "limit" => 5, "sort" => "newest"}
          ]
        }
      ],
      campaign_definition: %{
        name: "Incident Postmortem Campaign",
        description: "On-demand postmortem generation from incident history.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"quest_name" => "Write Incident Postmortem", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp release_notes do
    %Board{
      id: "release_notes",
      name: "Release Notes Generator",
      category: :generation,
      description:
        "Generate structured release notes from recent commits and code review findings. Produces user-facing changelog entries.",
      suggested_team: "Code Review guild. Any code-aware members work.",
      requires: [
        {:source_type, "git"}
      ],
      quest_definitions: [
        %{
          name: "Generate Release Notes",
          description: """
          Generate release notes from recent commits and code review findings. Include:
          - New features (user-facing, described in plain language)
          - Bug fixes (what was broken, what's fixed)
          - Breaking changes (clearly flagged)
          - Performance improvements
          - Internal changes (brief, for developers)
          Write the features section for end users, everything else for developers.
          """,
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Release Notes — {date}",
          log_title_template: nil,
          context_providers: [
            %{"type" => "quest_history", "limit" => 20},
            %{"type" => "lore", "tags" => ["code-quality"], "limit" => 5, "sort" => "newest"}
          ]
        }
      ],
      campaign_definition: %{
        name: "Release Notes Campaign",
        description: "On-demand release notes from recent commits and review history.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"quest_name" => "Generate Release Notes", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp threat_model_report do
    %Board{
      id: "threat_model_report",
      name: "Threat Model Report",
      category: :generation,
      description:
        "Generate a threat model for your codebase or system design. Identifies attack surfaces, trust boundaries, and prioritized mitigations.",
      suggested_team: "Risk Assessment guild. Security-aware members work well.",
      requires: [
        {:source_type, "git"}
      ],
      quest_definitions: [
        %{
          name: "Threat Model Analysis",
          description: "Analyze the codebase for threat modeling input — entry points, data flows, and trust boundaries.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Write Threat Model Report",
          description: """
          Write a structured threat model report. Include:
          - System overview and trust boundaries
          - Attack surface inventory (entry points, APIs, data stores)
          - Threat enumeration using STRIDE (Spoofing, Tampering, Repudiation, Info Disclosure, DoS, Elevation)
          - Risk ratings per threat (likelihood × impact)
          - Top 5 prioritized mitigations with effort estimates
          """,
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "replace",
          entry_title_template: "Threat Model — Current",
          log_title_template: nil,
          context_providers: [
            %{"type" => "quest_history", "limit" => 10},
            %{"type" => "lore", "tags" => ["security", "risk"], "limit" => 5, "sort" => "importance"}
          ]
        }
      ],
      campaign_definition: %{
        name: "Threat Model Campaign",
        description: "On-demand threat model generation — analysis then structured report.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"quest_name" => "Threat Model Analysis", "flow" => "always"},
          %{"quest_name" => "Write Threat Model Report", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp onboarding_brief do
    %Board{
      id: "onboarding_brief",
      name: "Team Onboarding Brief",
      category: :generation,
      description:
        "Generate a new member onboarding brief from your guild's lore and quest history. Captures institutional knowledge so new team members get up to speed fast.",
      suggested_team: "Works with any guild.",
      requires: [],
      quest_definitions: [
        %{
          name: "Write Onboarding Brief",
          description: """
          Write a team onboarding brief for a new team member. Cover:
          - What this team/guild does and why it matters
          - Key workflows and how decisions get made
          - Known patterns, gotchas, and things to watch for
          - Where to find information (key lore entries)
          - First week focus areas
          Keep it practical. Write it for someone smart but with zero context.
          """,
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "replace",
          entry_title_template: "Onboarding Brief — Current",
          log_title_template: nil,
          context_providers: [
            %{"type" => "quest_history", "limit" => 20},
            %{"type" => "lore", "tags" => [], "limit" => 10, "sort" => "importance"}
          ]
        }
      ],
      campaign_definition: %{
        name: "Onboarding Brief Campaign",
        description: "On-demand onboarding brief from guild lore and quest history.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"quest_name" => "Write Onboarding Brief", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end
end
```

**Step 2: Compile + commit**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix compile 2>&1 | grep error | head -10 && git add lib/ex_calibur/board/generation.ex && git commit -m "feat: Quest Board generation templates (postmortem, release notes, threat model, onboarding brief)"' --pane=main:1.3
```

---

## Task 7: Board Templates — Review

**Files:**
- Create: `lib/ex_calibur/board/review.ex`

**Step 1: Create the review templates file**

```elixir
defmodule ExCalibur.Board.Review do
  @moduledoc "Continuous review pipeline campaign templates."

  alias ExCalibur.Board

  def templates do
    [
      pr_review_pipeline(),
      url_change_review(),
      content_safety_webhook(),
      compliance_monitor()
    ]
  end

  defp pr_review_pipeline do
    %Board{
      id: "pr_review_pipeline",
      name: "PR Review Pipeline",
      category: :review,
      description:
        "Full PR review via GitHub webhook — quick scan on every PR, full consensus review for flagged ones, with a GitHub PR comment posted back.",
      suggested_team: "Code Review guild is ideal.",
      requires: [
        {:source_type, "webhook"},
        {:herald_type, "github_pr"}
      ],
      quest_definitions: [
        %{
          name: "PR Quick Scan",
          description: "Quick automated PR scan — does this need a full review?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
          source_ids: []
        },
        %{
          name: "PR Full Review",
          description: "Full consensus PR review — correctness, style, security, performance.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Post PR Review Comment",
          description: "Post the full review as a GitHub PR comment.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "github_pr",
          herald_name: "github_pr:default"
        }
      ],
      campaign_definition: %{
        name: "PR Review Pipeline Campaign",
        description: "Webhook-triggered PR review with GitHub comment for flagged PRs.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "PR Quick Scan", "flow" => "always"},
          %{"quest_name" => "PR Full Review", "flow" => "on_flag"},
          %{"quest_name" => "Post PR Review Comment", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp url_change_review do
    %Board{
      id: "url_change_review",
      name: "URL Change Monitor",
      category: :review,
      description:
        "Monitor URLs for content changes and assess their impact. Useful for tracking competitor sites, regulatory pages, or API documentation.",
      suggested_team: "Any guild with content or risk awareness.",
      requires: [
        {:source_type, "url"},
        {:herald_type, "slack"}
      ],
      quest_definitions: [
        %{
          name: "URL Change Quick Assessment",
          description: "Quick assessment of a detected URL change — is this significant?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
          source_ids: []
        },
        %{
          name: "URL Change Full Review",
          description: "Full review of a significant URL change — impact and recommended response.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Post URL Change Alert",
          description: "Post URL change assessment to team Slack.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "slack",
          herald_name: "slack:default"
        }
      ],
      campaign_definition: %{
        name: "URL Change Monitor Campaign",
        description: "URL change detection with Slack alert for significant changes.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "URL Change Quick Assessment", "flow" => "always"},
          %{"quest_name" => "URL Change Full Review", "flow" => "on_flag"},
          %{"quest_name" => "Post URL Change Alert", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp content_safety_webhook do
    %Board{
      id: "content_safety_webhook",
      name: "Content Safety Review",
      category: :review,
      description:
        "Review user-submitted content via webhook for safety violations. Quick automated scan with full review and Slack escalation for flagged content.",
      suggested_team: "Content Moderation guild is ideal.",
      requires: [
        {:source_type, "webhook"},
        {:herald_type, "slack"}
      ],
      quest_definitions: [
        %{
          name: "Content Safety Quick Scan",
          description: "Quick automated safety scan of submitted content.",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
          source_ids: []
        },
        %{
          name: "Content Safety Full Review",
          description: "Full consensus safety review of flagged content.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Escalate Content Violation",
          description: "Escalate confirmed content safety violation to team Slack.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "slack",
          herald_name: "slack:default"
        }
      ],
      campaign_definition: %{
        name: "Content Safety Campaign",
        description: "Webhook-triggered content safety review with Slack escalation.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "Content Safety Quick Scan", "flow" => "always"},
          %{"quest_name" => "Content Safety Full Review", "flow" => "on_flag"},
          %{"quest_name" => "Escalate Content Violation", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp compliance_monitor do
    %Board{
      id: "compliance_monitor",
      name: "Compliance Monitor",
      category: :review,
      description:
        "Continuous compliance monitoring from regulatory feeds. Hourly scan for changes to rules, advisories, or standards that affect your operations.",
      suggested_team: "Risk Assessment or Contract Review guild.",
      requires: [
        {:source_type, "feed"},
        {:herald_type, "slack"}
      ],
      quest_definitions: [
        %{
          name: "Compliance Feed Quick Scan",
          description: "Quick scan of incoming regulatory/compliance feed entry — does this affect us?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          context_providers: [
            %{"type" => "lore", "tags" => ["compliance", "risk"], "limit" => 3, "sort" => "importance"}
          ]
        },
        %{
          name: "Compliance Full Assessment",
          description: "Full assessment of a compliance signal — impact, required response, and timeline.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Post Compliance Alert",
          description: "Post compliance finding and recommended action to team Slack.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "slack",
          herald_name: "slack:default"
        }
      ],
      campaign_definition: %{
        name: "Compliance Monitor Campaign",
        description: "Feed-triggered compliance monitoring with Slack alerts.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "Compliance Feed Quick Scan", "flow" => "always"},
          %{"quest_name" => "Compliance Full Assessment", "flow" => "on_flag"},
          %{"quest_name" => "Post Compliance Alert", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end
end
```

**Step 2: Compile + commit**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix compile 2>&1 | grep error | head -10 && git add lib/ex_calibur/board/review.ex && git commit -m "feat: Quest Board review templates (PR pipeline, URL monitor, content safety, compliance)"' --pane=main:1.3
```

---

## Task 8: Board Templates — Onboarding

**Files:**
- Create: `lib/ex_calibur/board/onboarding.ex`

**Step 1: Create the onboarding templates file**

```elixir
defmodule ExCalibur.Board.Onboarding do
  @moduledoc "Initial setup and orientation campaign templates."

  alias ExCalibur.Board

  def templates do
    [
      team_health_check(),
      codebase_first_look(),
      security_baseline_scan(),
      knowledge_base_bootstrap()
    ]
  end

  defp team_health_check do
    %Board{
      id: "team_health_check",
      name: "Team Health Check",
      category: :onboarding,
      description:
        "Assess your current guild's member coverage, capability gaps, and recommended additions. Run this after installing a guild to understand what you have.",
      suggested_team: "Works with any guild — needs at least one active member.",
      requires: [
        :any_members
      ],
      quest_definitions: [
        %{
          name: "Team Coverage Analysis",
          description:
            "Analyze the current team's member coverage — what capabilities are present, what gaps exist, and what additional members would strengthen the guild.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Write Team Health Report",
          description: """
          Write a team health report covering:
          - Current member roster and their strengths
          - Coverage gaps by domain (security, performance, compliance, etc.)
          - Recommended additional members with suggested system prompts
          - Quick wins — things this team can tackle right now
          """,
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "replace",
          entry_title_template: "Team Health — Current",
          log_title_template: nil
        }
      ],
      campaign_definition: %{
        name: "Team Health Check Campaign",
        description: "On-demand team capability assessment and gap analysis.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"quest_name" => "Team Coverage Analysis", "flow" => "always"},
          %{"quest_name" => "Write Team Health Report", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp codebase_first_look do
    %Board{
      id: "codebase_first_look",
      name: "Codebase First Look",
      category: :onboarding,
      description:
        "Initial codebase quality and architecture audit. Run this when connecting a new repository to get an immediate lay of the land.",
      suggested_team: "Code Review guild. Any code-aware members work.",
      requires: [
        {:source_type, "git"}
      ],
      quest_definitions: [
        %{
          name: "Codebase Architecture Review",
          description:
            "Review the codebase for architecture, patterns, quality, and immediate concerns. What is this project, how is it structured, and what stands out?",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Write Codebase Summary",
          description: """
          Write a codebase first-look summary. Include:
          - What this project does (1 paragraph)
          - Architecture overview (key modules, patterns, dependencies)
          - Code quality assessment (strengths and concerns)
          - Security red flags (if any)
          - Top 5 areas to investigate further
          Write for someone joining the project today.
          """,
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Codebase First Look — {date}",
          log_title_template: nil
        }
      ],
      campaign_definition: %{
        name: "Codebase First Look Campaign",
        description: "On-demand initial codebase audit and architectural summary.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"quest_name" => "Codebase Architecture Review", "flow" => "always"},
          %{"quest_name" => "Write Codebase Summary", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp security_baseline_scan do
    %Board{
      id: "security_baseline_scan",
      name: "Security Baseline Scan",
      category: :onboarding,
      description:
        "Establish a security baseline for a new codebase — identifies immediate risks, flags known vulnerability patterns, and creates a living baseline document.",
      suggested_team: "Risk Assessment or Dependency Audit guild.",
      requires: [
        {:source_type, "git"},
        {:herald_type, "slack"}
      ],
      quest_definitions: [
        %{
          name: "Security Baseline Assessment",
          description:
            "Assess the codebase for security vulnerabilities, risky patterns, exposed secrets, and dependency risks.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Write Security Baseline",
          description: """
          Write the security baseline document. Include:
          - Security posture rating (1-5)
          - Critical findings (must fix before production)
          - High-priority findings (fix within sprint)
          - Dependency vulnerability summary
          - Positive security practices already in place
          - Baseline metrics for future comparison
          """,
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "replace",
          entry_title_template: "Security Baseline — Current",
          log_title_template: nil,
          context_providers: [
            %{"type" => "lore", "tags" => ["security"], "limit" => 5, "sort" => "importance"}
          ]
        },
        %{
          name: "Post Security Baseline Alert",
          description: "Post critical security findings to team Slack for immediate awareness.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "slack",
          herald_name: "slack:default"
        }
      ],
      campaign_definition: %{
        name: "Security Baseline Campaign",
        description: "On-demand security baseline with Slack alert for critical findings.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"quest_name" => "Security Baseline Assessment", "flow" => "always"},
          %{"quest_name" => "Write Security Baseline", "flow" => "always"},
          %{"quest_name" => "Post Security Baseline Alert", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp knowledge_base_bootstrap do
    %Board{
      id: "knowledge_base_bootstrap",
      name: "Knowledge Base Bootstrap",
      category: :onboarding,
      description:
        "Seed your guild's knowledge base with initial lore from the codebase and configuration. Gives every future quest a head start with institutional context.",
      suggested_team: "Works with any guild.",
      requires: [
        {:source_type, "git"}
      ],
      quest_definitions: [
        %{
          name: "Extract Initial Knowledge",
          description: "Extract key knowledge from the codebase — architecture patterns, domain concepts, and operational context — to seed the knowledge base.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Knowledge Seed — {date}",
          log_title_template: nil
        },
        %{
          name: "Extract Domain Glossary",
          description: """
          Extract a domain glossary from the codebase. For each key term:
          - Term name
          - What it means in this codebase's context
          - Where it's used (modules, files, database tables)
          - How it relates to adjacent concepts
          Focus on domain terms, not technical ones. These help new members onboard faster.
          """,
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Domain Glossary — {date}",
          log_title_template: nil
        }
      ],
      campaign_definition: %{
        name: "Knowledge Base Bootstrap Campaign",
        description: "On-demand knowledge base seeding from codebase — architecture + domain glossary.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"quest_name" => "Extract Initial Knowledge", "flow" => "always"},
          %{"quest_name" => "Extract Domain Glossary", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end
end
```

**Step 2: Compile all board modules**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix compile 2>&1 | grep -E "error|warning" | head -20' --pane=main:1.3`
Expected: Clean compile

**Step 3: Verify Board.all/0 returns 20 templates in iex**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_calibur && echo "ExCalibur.Board.all() |> length()" | mix run --no-start /dev/stdin 2>/dev/null' --pane=main:1.3`

(Or test in iex: `ExCalibur.Board.all() |> Enum.map(& &1.id)`)

**Step 4: Commit**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && git add lib/ex_calibur/board/onboarding.ex && git commit -m "feat: Quest Board onboarding templates (team health, first look, security baseline, knowledge bootstrap)"' --pane=main:1.3
```

---

## Task 9: QuestBoardLive

**Files:**
- Create: `lib/ex_calibur_web/live/quest_board_live.ex`

**Step 1: Create the LiveView**

```elixir
defmodule ExCaliburWeb.QuestBoardLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge

  alias ExCalibur.Board
  alias ExCalibur.Quests

  @categories [
    triage: "Triage",
    reporting: "Reporting",
    generation: "Generation",
    review: "Review",
    onboarding: "Onboarding"
  ]

  @impl true
  def mount(_params, _session, socket) do
    templates = Board.all()
    templates_with_status = Enum.map(templates, &with_status/1)

    {:ok,
     assign(socket,
       page_title: "Quest Board",
       templates: templates_with_status,
       active_category: nil,
       show_unavailable: false,
       installing: nil,
       installed: MapSet.new()
     )}
  end

  @impl true
  def handle_event("filter_category", %{"category" => cat}, socket) do
    cat_atom = if cat == "", do: nil, else: String.to_existing_atom(cat)
    {:noreply, assign(socket, active_category: cat_atom)}
  end

  @impl true
  def handle_event("toggle_unavailable", _params, socket) do
    {:noreply, assign(socket, show_unavailable: !socket.assigns.show_unavailable)}
  end

  @impl true
  def handle_event("install_template", %{"id" => id}, socket) do
    case Board.get(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Template not found")}

      template ->
        case Board.install(template) do
          {:ok, _campaign} ->
            installed = MapSet.put(socket.assigns.installed, id)

            {:noreply,
             socket
             |> assign(installed: installed, installing: nil)
             |> put_flash(:info, "\"#{template.name}\" installed! Find it in Quests.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Install failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("confirm_install", %{"id" => id}, socket) do
    {:noreply, assign(socket, installing: id)}
  end

  @impl true
  def handle_event("cancel_install", _params, socket) do
    {:noreply, assign(socket, installing: nil)}
  end

  defp with_status(template) do
    requirements = Board.check_requirements(template)
    readiness = Board.readiness(template)
    %{template: template, requirements: requirements, readiness: readiness}
  end

  defp visible_templates(templates, active_category, show_unavailable) do
    templates
    |> Enum.filter(fn %{template: t, readiness: r} ->
      category_match = is_nil(active_category) || t.category == active_category
      availability_match = show_unavailable || r != :unavailable
      category_match && availability_match
    end)
  end

  defp category_label(cat), do: @categories[cat] || to_string(cat)

  defp readiness_badge(:ready), do: {"Ready", "default"}
  defp readiness_badge(:almost), do: {"Almost", "secondary"}
  defp readiness_badge(:unavailable), do: {"Missing", "outline"}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Quest Board</h1>
        <p class="text-muted-foreground mt-1.5">
          Pre-configured campaign templates. Install one to add it to your existing guild's quests.
        </p>
      </div>

      <%# Category filter + unavailable toggle %>
      <div class="flex flex-wrap items-center gap-2">
        <button
          phx-click="filter_category"
          phx-value-category=""
          class={[
            "px-3 py-1.5 text-sm rounded-md transition-colors",
            is_nil(@active_category)
              && "bg-accent text-foreground font-medium"
              || "text-muted-foreground hover:bg-accent hover:text-foreground"
          ]}
        >
          All
        </button>
        <%= for {cat, label} <- [triage: "Triage", reporting: "Reporting", generation: "Generation", review: "Review", onboarding: "Onboarding"] do %>
          <button
            phx-click="filter_category"
            phx-value-category={cat}
            class={[
              "px-3 py-1.5 text-sm rounded-md transition-colors",
              @active_category == cat
                && "bg-accent text-foreground font-medium"
                || "text-muted-foreground hover:bg-accent hover:text-foreground"
            ]}
          >
            {label}
          </button>
        <% end %>

        <div class="ml-auto flex items-center gap-2 text-sm text-muted-foreground">
          <button
            phx-click="toggle_unavailable"
            class="hover:text-foreground transition-colors"
          >
            {if @show_unavailable, do: "Hide unavailable", else: "Show all"}
          </button>
        </div>
      </div>

      <%# Template list %>
      <div class="space-y-3">
        <%= for %{template: t, requirements: reqs, readiness: r} <- visible_templates(@templates, @active_category, @show_unavailable) do %>
          <div class={[
            "flex flex-col gap-4 rounded-lg border p-5 sm:flex-row sm:items-start sm:justify-between",
            MapSet.member?(@installed, t.id) && "border-primary bg-accent/50",
            r == :unavailable && "opacity-60"
          ]}>
            <div class="space-y-2 flex-1 min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="font-semibold">{t.name}</span>
                <.badge variant="outline" class="text-xs capitalize">{category_label(t.category)}</.badge>
                <%= if MapSet.member?(@installed, t.id) do %>
                  <.badge variant="default">Installed</.badge>
                <% else %>
                  <% {label, variant} = readiness_badge(r) %>
                  <.badge variant={variant}>{label}</.badge>
                <% end %>
              </div>

              <p class="text-sm text-muted-foreground">{t.description}</p>

              <%= if t.suggested_team && t.suggested_team != "" do %>
                <p class="text-xs text-muted-foreground italic">
                  Team: {t.suggested_team}
                </p>
              <% end %>

              <%= if length(reqs) > 0 do %>
                <div class="flex flex-wrap gap-1.5 mt-1">
                  <%= for {met, label} <- reqs do %>
                    <.badge variant={if met, do: "secondary", else: "outline"} class="text-xs gap-1">
                      {if met, do: "✓", else: "○"} {label}
                    </.badge>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="ml-4 shrink-0 self-center">
              <%= if MapSet.member?(@installed, t.id) do %>
                <.button variant="outline" size="sm" disabled>
                  Installed
                </.button>
              <% else %>
                <%= if @installing == t.id do %>
                  <div class="flex gap-2">
                    <.button
                      variant="destructive"
                      size="sm"
                      phx-click="install_template"
                      phx-value-id={t.id}
                    >
                      Confirm
                    </.button>
                    <.button variant="outline" size="sm" phx-click="cancel_install">
                      Cancel
                    </.button>
                  </div>
                <% else %>
                  <.button
                    variant={if r == :ready, do: "default", else: "outline"}
                    size="sm"
                    phx-click="confirm_install"
                    phx-value-id={t.id}
                    disabled={r == :unavailable}
                  >
                    Install
                  </.button>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>

        <%= if visible_templates(@templates, @active_category, @show_unavailable) == [] do %>
          <div class="text-center py-12 text-muted-foreground">
            <p class="text-sm">No templates available in this category.</p>
            <button phx-click="toggle_unavailable" class="text-sm underline mt-1">
              Show all templates
            </button>
          </div>
        <% end %>
      </div>

      <div class="text-xs text-muted-foreground border-t pt-4">
        Installing a template adds new quests and a campaign to your existing guild. It does not replace current members or quests.
        <a href="/quests" class="underline ml-1">View Quests →</a>
      </div>
    </div>
    """
  end
end
```

**Step 2: Compile check**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix compile 2>&1 | grep -E "error|warning" | head -20' --pane=main:1.3`

**Step 3: Commit**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && git add lib/ex_calibur_web/live/quest_board_live.ex && git commit -m "feat: QuestBoardLive — browse and install campaign templates by category"' --pane=main:1.3
```

---

## Task 10: Router + Nav

**Files:**
- Modify: `lib/ex_calibur_web/router.ex`
- Modify: `lib/ex_calibur_web/components/layouts/root.html.heex`

**Step 1: Add route to router.ex**

In `lib/ex_calibur_web/router.ex`, add after the `/quests` route:

```elixir
live "/quest-board", QuestBoardLive, :index
```

**Step 2: Add nav link to root.html.heex**

In `root.html.heex`, add `{"Quest Board", "/quest-board"}` to the nav list after `{"Quests", "/quests"}`:

```heex
{"Lodge", "/lodge"},
{"Members", "/members"},
{"Quests", "/quests"},
{"Quest Board", "/quest-board"},
{"Grimoire", "/grimoire"},
{"Library", "/library"},
{"Town Square", "/town-square"},
{"Guild Hall", "/guild-hall"}
```

**Step 3: Compile + smoke test**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix compile 2>&1 | grep -E "error" | head -10' --pane=main:1.3`

**Step 4: Commit**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && git add lib/ex_calibur_web/router.ex lib/ex_calibur_web/components/layouts/root.html.heex && git commit -m "feat: add /quest-board route and nav link"' --pane=main:1.3
```

---

## Task 11: Tests

**Files:**
- Create: `test/ex_calibur_web/live/quest_board_live_test.exs`
- Create: `test/ex_calibur/board_test.exs`

**Step 1: Write the Board module test**

```elixir
defmodule ExCalibur.BoardTest do
  use ExCalibur.DataCase, async: true

  alias ExCalibur.Board

  describe "all/0" do
    test "returns at least 16 templates" do
      assert length(Board.all()) >= 16
    end

    test "all templates have required fields" do
      for t <- Board.all() do
        assert is_binary(t.id), "#{t.id} missing id"
        assert is_binary(t.name), "#{t.id} missing name"
        assert t.category in [:triage, :reporting, :generation, :review, :onboarding],
               "#{t.id} has invalid category #{t.category}"

        assert is_list(t.quest_definitions), "#{t.id} missing quest_definitions"
        assert length(t.quest_definitions) > 0, "#{t.id} has no quest_definitions"
        assert is_map(t.campaign_definition), "#{t.id} missing campaign_definition"
      end
    end

    test "all template ids are unique" do
      ids = Enum.map(Board.all(), & &1.id)
      assert length(ids) == length(Enum.uniq(ids))
    end
  end

  describe "by_category/1" do
    test "returns only templates for that category" do
      triage = Board.by_category(:triage)
      assert length(triage) > 0
      assert Enum.all?(triage, &(&1.category == :triage))
    end
  end

  describe "get/1" do
    test "finds template by id" do
      template = Board.get("jira_ticket_triage")
      assert template.name == "Jira Ticket Triage"
    end

    test "returns nil for unknown id" do
      assert Board.get("nonexistent") == nil
    end
  end

  describe "check_requirements/1" do
    test "returns list of {met, label} tuples" do
      template = Board.get("incident_postmortem")
      # no requirements
      assert Board.check_requirements(template) == []
    end

    test "returns false for missing source type" do
      template = Board.get("jira_ticket_triage")
      results = Board.check_requirements(template)
      # no sources configured in test DB
      assert Enum.all?(results, fn {met, _} -> !met end)
    end
  end

  describe "readiness/1" do
    test "returns :ready for template with no requirements" do
      template = Board.get("incident_postmortem")
      assert Board.readiness(template) == :ready
    end

    test "returns :unavailable when all requirements missing" do
      template = Board.get("jira_ticket_triage")
      # requires webhook source + slack herald, neither configured
      assert Board.readiness(template) == :unavailable
    end
  end
end
```

**Step 2: Run Board test to make sure it fails first**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test test/ex_calibur/board_test.exs 2>&1 | tail -20' --pane=main:1.3`
Expected: Tests pass (or compile errors to fix)

**Step 3: Write the LiveView test**

```elixir
defmodule ExCaliburWeb.QuestBoardLiveTest do
  use ExCaliburWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    ExCalibur.Repo.delete_all(ExCalibur.Quests.CampaignRun)
    ExCalibur.Repo.delete_all(ExCalibur.Quests.QuestRun)
    ExCalibur.Repo.delete_all(ExCalibur.Quests.Campaign)
    ExCalibur.Repo.delete_all(ExCalibur.Quests.Quest)
    :ok
  end

  test "renders quest board with templates", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/quest-board")

    assert html =~ "Quest Board"
    assert html =~ "Triage"
    assert html =~ "Reporting"
    assert html =~ "Generation"
    assert html =~ "Review"
    assert html =~ "Onboarding"
  end

  test "shows category filter buttons", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/quest-board")
    assert html =~ "All"
    assert html =~ "Triage"
    assert html =~ "Onboarding"
  end

  test "filters by category", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/quest-board")

    html = view |> element("button", "Triage") |> render_click()
    assert html =~ "Jira Ticket Triage"
    refute html =~ "Weekly Security Digest"
  end

  test "shows unavailable templates when toggled", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/quest-board")

    # By default, unavailable templates may be hidden — click show all
    html = view |> element("button", "Show all") |> render_click()
    # After toggle, unavailable templates should appear
    assert html =~ "Jira Ticket Triage"
  end

  test "can install a no-requirement template", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/quest-board")

    # Filter to onboarding to find incident_postmortem (no requirements)
    view |> element("button", "Generation") |> render_click()

    # Click Install on the Incident Postmortem template
    view
    |> element("[phx-value-id='incident_postmortem']", "Install")
    |> render_click()

    # Confirm the install
    html =
      view
      |> element("[phx-click='install_template'][phx-value-id='incident_postmortem']")
      |> render_click()

    assert html =~ "installed"
  end
end
```

**Step 4: Run all tests**

Run: `tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test 2>&1 | tail -30' --pane=main:1.3`
Expected: All pass

**Step 5: Commit**

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && git add test/ex_calibur/board_test.exs test/ex_calibur_web/live/quest_board_live_test.exs && git commit -m "test: Quest Board module and LiveView tests"' --pane=main:1.3
```

---

## Final Check

Run the full test suite one last time:

```bash
tmux-cli send 'cd /home/andrew/projects/ex_calibur && mix test 2>&1 | tail -10' --pane=main:1.3
```

Then visit `/quest-board` in the browser to smoke test the UI.
