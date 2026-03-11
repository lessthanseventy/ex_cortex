defmodule ExCalibur.Charters.ProductIntelligence do
  @moduledoc """
  Product intelligence guild charter.

  Uses builtin members: feedback-analyst, risk-assessor,
  trend-spotter, competitive-analyst.
  """

  alias ExCalibur.Members.BuiltinMember

  def metadata do
    members = [
      BuiltinMember.get("feedback-analyst"),
      BuiltinMember.get("risk-assessor"),
      BuiltinMember.get("trend-spotter"),
      BuiltinMember.get("competitive-analyst")
    ]

    %{
      banner: :business,
      name: "Product Intelligence",
      description:
        "Product intelligence guild — synthesizes user feedback, market trends, and competitive signals into actionable insight.",
      roles: Enum.map(members, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    members = [
      {"feedback-analyst", "Feedback Analyst"},
      {"risk-assessor", "Risk Assessor"},
      {"trend-spotter", "Trend Spotter"},
      {"competitive-analyst", "Competitive Analyst"}
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
        name: "Feedback Quick Scan",
        description: "Quick feedback scan triggered by incoming source data",
        status: "active",
        trigger: "source",
        schedule: nil,
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Product Intelligence Report",
        description: "Synthesize intelligence into a running product intelligence log",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "both",
        entry_title_template: "Product Intelligence",
        log_title_template: "Intelligence Log — {date}",
        context_providers: [
          %{"type" => "lore", "tags" => ["product", "feedback", "market"], "limit" => 5, "sort" => "top"}
        ],
        loop_mode: "reflect",
        loop_tools: ["query_lore"]
      },
      %{
        name: "Full Intelligence Review",
        description: "Full product intelligence review by all members reaching consensus",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Weekly Product Intelligence",
        description: "Weekly product intelligence synthesis campaign",
        status: "active",
        trigger: "scheduled",
        schedule: "@weekly",
        steps: [
          %{"quest_name" => "Feedback Quick Scan", "flow" => "always"},
          %{"quest_name" => "Full Intelligence Review", "flow" => "always"},
          %{"quest_name" => "Product Intelligence Report", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
