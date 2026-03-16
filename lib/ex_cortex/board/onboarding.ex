defmodule ExCortex.Board.Onboarding do
  @moduledoc "Initial setup and orientation thought templates."

  alias ExCortex.Board

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
      lobe: :business,
      name: "Team Health Check",
      category: :onboarding,
      description:
        "Assess your current cluster's neuron coverage, capability gaps, and recommended additions. Run this after installing a cluster to understand what you have.",
      suggested_team: "Works with any cluster — needs at least one active neuron.",
      requires: [
        :any_members
      ],
      step_definitions: [
        %{
          name: "Team Coverage Analysis",
          description:
            "Analyze the current team's neuron coverage — what capabilities are present, what gaps exist, and what additional neurons would strengthen the cluster.",
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
          - Current neuron roster and their strengths
          - Coverage gaps by domain (security, performance, compliance, etc.)
          - Recommended additional neurons with suggested system prompts
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
      rumination_definition: %{
        name: "Team Health Check",
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
      lobe: :business,
      name: "Codebase First Look",
      category: :onboarding,
      description:
        "Initial codebase quality and architecture audit. Run this when connecting a new repository to get an immediate lay of the land.",
      suggested_team: "Code Review cluster. Any code-aware neurons work.",
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
      rumination_definition: %{
        name: "Codebase First Look",
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
      lobe: :business,
      name: "Security Baseline Scan",
      category: :onboarding,
      description:
        "Establish a security baseline for a new codebase — identifies immediate risks, flags known vulnerability patterns, and creates a living baseline document.",
      suggested_team: "Risk Assessment or Dependency Audit cluster.",
      requires: [
        {:source_type, "git"},
        {:expression_type, "slack"}
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
            %{"type" => "memory", "tags" => ["security"], "limit" => 5, "sort" => "importance"}
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
          expression_name: "slack:default"
        }
      ],
      rumination_definition: %{
        name: "Security Baseline",
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
      lobe: :business,
      name: "Knowledge Base Bootstrap",
      category: :onboarding,
      description:
        "Seed your cluster's knowledge base with initial memory from the codebase and configuration. Gives every future thought a head start with institutional context.",
      suggested_team: "Works with any cluster.",
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
          Focus on domain terms, not technical ones. These help new neurons onboard faster.
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
      rumination_definition: %{
        name: "Knowledge Base Bootstrap",
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
