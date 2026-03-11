defmodule ExCalibur.Charters.PlatformGuild do
  @moduledoc """
  Backend, infrastructure, and platform reliability review guild charter.

  Uses builtin members: backend-reviewer, devops-reviewer,
  performance-auditor, security-skeptic.
  """

  alias ExCalibur.Members.BuiltinMember

  def metadata do
    members = [
      BuiltinMember.get("backend-reviewer"),
      BuiltinMember.get("devops-reviewer"),
      BuiltinMember.get("performance-auditor"),
      BuiltinMember.get("security-skeptic")
    ]

    %{
      name: "Platform Guild",
      description:
        "Backend, infrastructure, and platform reliability review guild — evaluates architecture, deployment, and performance.",
      roles: Enum.map(members, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    members = [
      {"backend-reviewer", "Backend Reviewer"},
      {"devops-reviewer", "DevOps Reviewer"},
      {"performance-auditor", "Performance Auditor"},
      {"security-skeptic", "Security Skeptic"}
    ]

    Enum.flat_map(members, fn {member_id, _name} ->
      builtin = BuiltinMember.get(member_id)

      [
        %{
          type: "role",
          name: builtin.name,
          status: "active",
          source: "db",
          config: %{
            "member_id" => member_id,
            "system_prompt" => builtin.system_prompt,
            "rank" => "apprentice",
            "model" => builtin.ranks.apprentice.model,
            "strategy" => builtin.ranks.apprentice.strategy,
            "tools" => "all_safe"
          }
        },
        %{
          type: "role",
          name: builtin.name,
          status: "active",
          source: "db",
          config: %{
            "member_id" => member_id,
            "system_prompt" => builtin.system_prompt,
            "rank" => "journeyman",
            "model" => builtin.ranks.journeyman.model,
            "strategy" => builtin.ranks.journeyman.strategy,
            "tools" => "all_safe"
          }
        }
      ]
    end)
  end

  def quest_definitions do
    [
      %{
        name: "Platform Quick Scan",
        description: "Quick automated platform health scan by apprentice members",
        status: "active",
        trigger: "scheduled",
        schedule: "@hourly",
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Full Platform Review",
        description: "Comprehensive platform review by all members reaching consensus",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Platform Health Report",
        description: "Synthesize platform health findings into a running lore log",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "both",
        entry_title_template: "Platform Health",
        log_title_template: "Platform Log — {date}",
        context_providers: [
          %{"type" => "lore", "tags" => ["platform", "security", "performance"], "limit" => 5, "sort" => "top"}
        ],
        loop_mode: "reflect",
        loop_tools: ["query_lore"]
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Platform Review Campaign",
        description: "Daily platform health review campaign",
        status: "active",
        trigger: "scheduled",
        schedule: "@daily",
        steps: [
          %{"quest_name" => "Platform Quick Scan", "flow" => "always"},
          %{"quest_name" => "Full Platform Review", "flow" => "on_flag"},
          %{"quest_name" => "Platform Health Report", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
