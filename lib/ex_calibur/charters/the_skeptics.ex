defmodule ExCalibur.Charters.TheSkeptics do
  @moduledoc """
  Pure skepticism guild charter.

  Uses builtin members: devils-advocate, challenger,
  evidence-collector, hype-detector.
  """

  alias ExCalibur.Members.BuiltinMember

  def metadata do
    members = [
      BuiltinMember.get("devils-advocate"),
      BuiltinMember.get("challenger"),
      BuiltinMember.get("evidence-collector"),
      BuiltinMember.get("hype-detector")
    ]

    %{
      banner: :tech,
      name: "The Skeptics",
      description: "Pure skepticism guild — challenges every claim, demands evidence, and deflates hype before it ships.",
      roles: Enum.map(members, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    members = [
      {"devils-advocate", "Devil's Advocate"},
      {"challenger", "Challenger"},
      {"evidence-collector", "Evidence Collector"},
      {"hype-detector", "Hype Detector"}
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
        name: "Quick Challenge",
        description: "Quick challenge by an apprentice skeptic",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Full Skeptic Panel",
        description: "Full skeptic panel — all members reach consensus",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Skeptic Findings",
        description: "Append skeptic review findings to the findings log",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Skeptic Review — {date}",
        context_providers: [
          %{"type" => "lore", "tags" => ["decisions", "findings"], "limit" => 5, "sort" => "importance"}
        ],
        loop_mode: "reflect",
        loop_tools: ["query_lore"]
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Skeptic Review Campaign",
        description: "Manual skeptic review — challenge, panel, and findings",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"quest_name" => "Quick Challenge", "flow" => "always"},
          %{"quest_name" => "Full Skeptic Panel", "flow" => "on_flag"},
          %{"quest_name" => "Skeptic Findings", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
