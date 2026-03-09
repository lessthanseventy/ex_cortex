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
            %{
              "type" => "lore",
              "tags" => ["security", "deps", "risk"],
              "limit" => 10,
              "sort" => "newest"
            }
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
      suggested_team: "Code Review guild. Works with any code-aware members.",
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
            %{
              "type" => "lore",
              "tags" => ["code-quality", "performance"],
              "limit" => 5,
              "sort" => "newest"
            }
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
      suggested_team: "Risk Assessment guild. Compliance-aware members work well.",
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
            %{
              "type" => "lore",
              "tags" => ["risk", "compliance", "deps"],
              "limit" => 10,
              "sort" => "importance"
            }
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
