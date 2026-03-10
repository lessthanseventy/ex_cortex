defmodule ExCalibur.Charters.EverydayCouncil do
  @moduledoc """
  Everyday Council guild charter.

  Your personal advisory board for life decisions, habits, and reflection.
  Uses builtin members: scope-realist, risk-assessor, the-optimist, challenger,
  evidence-collector, life-coach, journal-keeper.
  """

  alias ExCalibur.Members.BuiltinMember

  def metadata do
    members = [
      BuiltinMember.get("scope-realist"),
      BuiltinMember.get("risk-assessor"),
      BuiltinMember.get("the-optimist"),
      BuiltinMember.get("challenger"),
      BuiltinMember.get("evidence-collector"),
      BuiltinMember.get("life-coach"),
      BuiltinMember.get("journal-keeper")
    ]

    %{
      name: "Everyday Council",
      description:
        "Your personal advisory board for life decisions, habits, and reflection. Helps you think through anything — from big choices to daily noise.",
      roles: Enum.map(members, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    members = [
      {"scope-realist", :journeyman},
      {"risk-assessor", :journeyman},
      {"the-optimist", :apprentice},
      {"challenger", :journeyman},
      {"evidence-collector", :apprentice},
      {"life-coach", :journeyman},
      {"journal-keeper", :apprentice}
    ]

    Enum.flat_map(members, fn {member_id, rank} ->
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
            "strategy" => builtin.ranks.apprentice.strategy
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
            "rank" => to_string(rank),
            "model" => builtin.ranks[rank].model,
            "strategy" => builtin.ranks[rank].strategy
          }
        }
      ]
    end)
  end

  def quest_definitions do
    [
      %{
        name: "Life Decision Review",
        description:
          "Submit a decision or dilemma for a full panel review. Each member evaluates from their perspective.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        output_type: "verdict"
      },
      %{
        name: "Quick Take",
        description: "Fast advisory from a single grounded perspective.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [
          %{
            "who" => "journeyman",
            "preferred_who" => "life-coach",
            "when" => "on_trigger",
            "how" => "solo"
          }
        ],
        source_ids: [],
        output_type: "verdict"
      },
      %{
        name: "Journal Intake",
        description: "Drop a link, note, doc, or thought. The journal keeper processes it into a structured lore entry.",
        status: "active",
        trigger: "source",
        schedule: nil,
        roster: [
          %{
            "who" => "apprentice",
            "preferred_who" => "journal-keeper",
            "when" => "on_trigger",
            "how" => "solo"
          }
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Journal — {date}"
      },
      %{
        name: "Weekly Reflection",
        description: "Weekly synthesis of accumulated journal entries into a reflection.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 9 * * 1",
        roster: [
          %{
            "who" => "journeyman",
            "preferred_who" => "the-historian",
            "when" => "on_trigger",
            "how" => "solo"
          }
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Weekly Reflection — {date}",
        context_providers: [%{"type" => "lore", "limit" => 20}]
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Intake Loop",
        description: "Continuous intake and weekly synthesis",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "Journal Intake", "flow" => "always"},
          %{"quest_name" => "Weekly Reflection", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
