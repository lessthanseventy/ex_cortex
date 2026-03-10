defmodule ExCalibur.Board.Onboarding do
  @moduledoc "Initial setup and orientation quest templates."

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
      step_definitions: [
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
      quest_definition: %{
        name: "Team Health Check Quest",
        description: "On-demand team capability assessment and gap analysis.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"step_name" => "Team Coverage Analysis", "flow" => "always"},
          %{"step_name" => "Write Team Health Report", "flow" => "always"}
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
      step_definitions: [
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
      quest_definition: %{
        name: "Codebase First Look Quest",
        description: "On-demand initial codebase audit and architectural summary.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"step_name" => "Codebase Architecture Review", "flow" => "always"},
          %{"step_name" => "Write Codebase Summary", "flow" => "always"}
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
      step_definitions: [
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
      quest_definition: %{
        name: "Security Baseline Quest",
        description: "On-demand security baseline with Slack alert for critical findings.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"step_name" => "Security Baseline Assessment", "flow" => "always"},
          %{"step_name" => "Write Security Baseline", "flow" => "always"},
          %{"step_name" => "Post Security Baseline Alert", "flow" => "on_flag"}
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
      step_definitions: [
        %{
          name: "Extract Initial Knowledge",
          description:
            "Extract key knowledge from the codebase — architecture patterns, domain concepts, and operational context — to seed the knowledge base.",
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
      quest_definition: %{
        name: "Knowledge Base Bootstrap Quest",
        description: "On-demand knowledge base seeding from codebase — architecture + domain glossary.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"step_name" => "Extract Initial Knowledge", "flow" => "always"},
          %{"step_name" => "Extract Domain Glossary", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end
end
