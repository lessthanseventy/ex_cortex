defmodule ExCalibur.Board.Generation do
  @moduledoc "On-demand artifact generation quest templates."

  alias ExCalibur.Board

  def templates do
    [
      incident_postmortem(),
      release_notes(),
      threat_model_report(),
      onboarding_brief(),
      weekly_digest(),
      platform_health()
    ]
  end

  defp incident_postmortem do
    %Board{
      id: "incident_postmortem",
      banner: :tech,
      name: "Incident Postmortem",
      category: :generation,
      description:
        "On-demand structured postmortem document from incident history and triage logs. Each run appends a new postmortem entry to the incident log.",
      suggested_team: "Incident Triage guild. Any members with system analysis capability work.",
      requires: [],
      step_definitions: [
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
      quest_definition: %{
        name: "Incident Postmortem Quest",
        description: "On-demand postmortem generation from incident history.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"step_name" => "Write Incident Postmortem", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp release_notes do
    %Board{
      id: "release_notes",
      banner: :tech,
      name: "Release Notes Generator",
      category: :generation,
      description:
        "Generate structured release notes from recent commits and code review findings. Produces user-facing changelog entries.",
      suggested_team: "Code Review guild. Any code-aware members work.",
      requires: [
        {:source_type, "git"}
      ],
      step_definitions: [
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
            %{
              "type" => "lore",
              "tags" => ["code-quality"],
              "limit" => 5,
              "sort" => "newest"
            }
          ]
        }
      ],
      quest_definition: %{
        name: "Release Notes Quest",
        description: "On-demand release notes from recent commits and review history.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"step_name" => "Generate Release Notes", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp threat_model_report do
    %Board{
      id: "threat_model_report",
      banner: :tech,
      name: "Threat Model Report",
      category: :generation,
      description:
        "Generate a threat model for your codebase or system design. Identifies attack surfaces, trust boundaries, and prioritized mitigations.",
      suggested_team: "Risk Assessment guild. Security-aware members work well.",
      requires: [
        {:source_type, "git"}
      ],
      step_definitions: [
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
            %{
              "type" => "lore",
              "tags" => ["security", "risk"],
              "limit" => 5,
              "sort" => "importance"
            }
          ]
        }
      ],
      quest_definition: %{
        name: "Threat Model Quest",
        description: "On-demand threat model generation — analysis then structured report.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"step_name" => "Threat Model Analysis", "flow" => "always"},
          %{"step_name" => "Write Threat Model Report", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp weekly_digest do
    %Board{
      id: "weekly_digest",
      banner: :tech,
      name: "Weekly Intelligence Digest",
      category: :generation,
      description:
        "Scheduled weekly synthesis of trends, feedback signals, and risks into a lore artifact. Pulls from your lore library to build institutional memory.",
      suggested_team: "Product Intelligence guild. Any guild with analyst members works.",
      requires: [:any_members],
      step_definitions: [
        %{
          name: "Trend Analysis",
          description: "Trend analysis — synthesize market and product signals from the past week.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{
              "who" => "master",
              "preferred_who" => "trend-spotter",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          context_providers: [
            %{"type" => "lore", "tags" => ["market", "trends"], "limit" => 5, "sort" => "top"}
          ]
        },
        %{
          name: "Write Weekly Digest",
          description: "Write the weekly digest artifact — append a new entry to the digest log.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "append",
          entry_title_template: "Weekly Digest — {date}",
          context_providers: [
            %{"type" => "quest_history", "limit" => 10},
            %{"type" => "lore", "tags" => [], "limit" => 5, "sort" => "top"}
          ]
        }
      ],
      quest_definition: %{
        name: "Weekly Intelligence Digest Quest",
        description: "Scheduled weekly trend analysis and digest generation.",
        status: "active",
        trigger: "scheduled",
        schedule: "@weekly",
        steps: [
          %{"step_name" => "Trend Analysis", "flow" => "always"},
          %{"step_name" => "Write Weekly Digest", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp platform_health do
    %Board{
      id: "platform_health",
      banner: :tech,
      name: "Platform Health Report",
      category: :generation,
      description:
        "Scheduled platform health synthesis — backend architecture, deployment health, and performance signals consolidated into a running lore log.",
      suggested_team: "Platform Guild is ideal.",
      requires: [:any_members],
      step_definitions: [
        %{
          name: "Platform Assessment",
          description: "Full consensus platform assessment — architecture, deployment, and performance.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: [],
          context_providers: [
            %{
              "type" => "lore",
              "tags" => ["platform", "performance", "security"],
              "limit" => 5,
              "sort" => "importance"
            }
          ]
        },
        %{
          name: "Write Platform Report",
          description: "Write the platform health report — both log entry and current snapshot.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "artifact",
          write_mode: "both",
          entry_title_template: "Platform Health",
          log_title_template: "Platform Log — {date}"
        }
      ],
      quest_definition: %{
        name: "Platform Health Report Quest",
        description: "Scheduled weekly platform assessment and health report.",
        status: "active",
        trigger: "scheduled",
        schedule: "@weekly",
        steps: [
          %{"step_name" => "Platform Assessment", "flow" => "always"},
          %{"step_name" => "Write Platform Report", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp onboarding_brief do
    %Board{
      id: "onboarding_brief",
      banner: :tech,
      name: "Team Onboarding Brief",
      category: :generation,
      description:
        "Generate a new member onboarding brief from your guild's lore and quest history. Captures institutional knowledge so new team members get up to speed fast.",
      suggested_team: "Works with any guild.",
      requires: [],
      step_definitions: [
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
      quest_definition: %{
        name: "Onboarding Brief Quest",
        description: "On-demand onboarding brief from guild lore and quest history.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"step_name" => "Write Onboarding Brief", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end
end
