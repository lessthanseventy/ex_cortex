defmodule ExCortex.Praxis.Generation do
  @moduledoc "On-demand artifact generation thought templates."

  alias ExCortex.Praxis

  def templates do
    [
      incident_postmortem(),
      release_notes(),
      threat_model_report(),
      onboarding_brief(),
      # weekly_digest removed — covered by Morning Briefing seed + digest reflexes
      platform_health()
    ]
  end

  defp incident_postmortem do
    %Praxis{
      id: "incident_postmortem",
      lobe: :frontal,
      name: "Incident Postmortem",
      category: :generation,
      description:
        "On-demand structured postmortem document from incident history and triage logs. Each run appends a new postmortem entry to the incident log.",
      suggested_team: "Incident Triage cluster. Any neurons with system analysis capability work.",
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
            %{"type" => "rumination_history", "limit" => 10},
            %{"type" => "memory", "tags" => ["incidents"], "limit" => 5, "sort" => "newest"}
          ]
        }
      ],
      rumination_definition: %{
        name: "Incident Postmortem",
        description: "On-demand postmortem generation from daydream history.",
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
    %Praxis{
      id: "release_notes",
      lobe: :frontal,
      name: "Release Notes Generator",
      category: :generation,
      description:
        "Generate structured release notes from recent commits and code review findings. Produces user-facing changelog entries.",
      suggested_team: "Code Review cluster. Any code-aware neurons work.",
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
            %{"type" => "rumination_history", "limit" => 20},
            %{
              "type" => "memory",
              "tags" => ["code-quality"],
              "limit" => 5,
              "sort" => "newest"
            }
          ]
        }
      ],
      rumination_definition: %{
        name: "Release Notes",
        description: "On-demand release notes from recent commits and review daydream history.",
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
    %Praxis{
      id: "threat_model_report",
      lobe: :frontal,
      name: "Threat Model Report",
      category: :generation,
      description:
        "Generate a threat model for your codebase or system design. Identifies attack surfaces, trust boundaries, and prioritized mitigations.",
      suggested_team: "Risk Assessment cluster. Security-aware neurons work well.",
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
            %{"type" => "rumination_history", "limit" => 10},
            %{
              "type" => "memory",
              "tags" => ["security", "risk"],
              "limit" => 5,
              "sort" => "importance"
            }
          ]
        }
      ],
      rumination_definition: %{
        name: "Threat Model",
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

  defp platform_health do
    %Praxis{
      id: "platform_health",
      lobe: :frontal,
      name: "Platform Health Report",
      category: :generation,
      description:
        "Scheduled platform health synthesis — backend architecture, deployment health, and performance signals consolidated into a running memory log.",
      suggested_team: "Platform Cluster is ideal.",
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
              "type" => "memory",
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
      rumination_definition: %{
        name: "Platform Health Report",
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
    %Praxis{
      id: "onboarding_brief",
      lobe: :frontal,
      name: "Team Onboarding Brief",
      category: :generation,
      description:
        "Generate a new neuron onboarding brief from your cluster's memory and daydream history. Captures institutional knowledge so new team neurons get up to speed fast.",
      suggested_team: "Works with any cluster.",
      requires: [],
      step_definitions: [
        %{
          name: "Write Onboarding Brief",
          description: """
          Write a team onboarding brief for a new team neuron. Cover:
          - What this team/cluster does and why it matters
          - Key workflows and how decisions get made
          - Known patterns, gotchas, and things to watch for
          - Where to find information (key memory engrams)
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
            %{"type" => "rumination_history", "limit" => 20},
            %{"type" => "memory", "tags" => [], "limit" => 10, "sort" => "importance"}
          ]
        }
      ],
      rumination_definition: %{
        name: "Onboarding Brief",
        description: "On-demand onboarding brief from cluster memory and daydream history.",
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
