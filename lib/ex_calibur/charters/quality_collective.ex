defmodule ExCalibur.Charters.QualityCollective do
  @moduledoc """
  Frontend quality and accessibility review guild charter.

  Uses builtin members: accessibility-auditor, frontend-reviewer,
  evidence-collector, the-nitpicker.
  """

  alias ExCalibur.Members.BuiltinMember

  def metadata do
    members = [
      BuiltinMember.get("accessibility-auditor"),
      BuiltinMember.get("frontend-reviewer"),
      BuiltinMember.get("evidence-collector"),
      BuiltinMember.get("the-nitpicker")
    ]

    %{
      banner: :tech,
      name: "Quality Collective",
      description:
        "Frontend quality and accessibility review guild — audits UI code for WCAG compliance, code quality, and evidence-backed findings.",
      roles: Enum.map(members, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    members = [
      {"accessibility-auditor", "Accessibility Auditor"},
      {"frontend-reviewer", "Frontend Reviewer"},
      {"evidence-collector", "Evidence Collector"},
      {"the-nitpicker", "The Nitpicker"}
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
        name: "A11y Quick Scan",
        description: "Quick automated accessibility scan by apprentice members",
        status: "active",
        trigger: "scheduled",
        schedule: "@hourly",
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        context_providers: [
          %{"type" => "lore", "tags" => ["a11y"], "limit" => 3, "sort" => "importance"}
        ],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Full Quality Review",
        description: "Comprehensive quality review by all members reaching consensus",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Quality Findings Log",
        description: "Synthesize quality findings into the quality log artifact",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "both",
        entry_title_template: "Quality Findings",
        log_title_template: "Quality Log — {date}",
        context_providers: [
          %{"type" => "lore", "tags" => ["a11y", "quality"], "limit" => 5, "sort" => "top"}
        ],
        loop_mode: "reflect",
        loop_tools: ["query_lore"]
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Quality Review Campaign",
        description: "Daily quality and accessibility review campaign",
        status: "active",
        trigger: "scheduled",
        schedule: "@daily",
        steps: [
          %{"quest_name" => "A11y Quick Scan", "flow" => "always"},
          %{"quest_name" => "Full Quality Review", "flow" => "on_flag"},
          %{"quest_name" => "Quality Findings Log", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
