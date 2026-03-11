defmodule ExCalibur.Charters.CultureDesk do
  @moduledoc """
  Culture Desk guild charter.

  Entertainment, music, film, culture. The tabloid voice meets the historian's
  memory. Uses builtin members: the-tabloid, the-historian, the-poet, brand-guardian.
  """

  alias ExCalibur.Members.BuiltinMember

  def metadata do
    members = [
      BuiltinMember.get("the-tabloid"),
      BuiltinMember.get("the-historian"),
      BuiltinMember.get("the-poet"),
      BuiltinMember.get("brand-guardian")
    ]

    %{
      name: "Culture Desk",
      description: "Entertainment, music, film, culture. The tabloid voice meets the historian's memory.",
      roles: Enum.map(members, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    members = [
      {"the-tabloid", :journeyman},
      {"the-historian", :apprentice},
      {"the-poet", :apprentice},
      {"brand-guardian", :apprentice}
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
            "rank" => to_string(rank),
            "model" => builtin.ranks[rank].model,
            "strategy" => builtin.ranks[rank].strategy,
            "tools" => "all_safe"
          }
        }
      ]
    end)
  end

  def quest_definitions do
    [
      %{
        name: "Culture Brief",
        description: "Pop culture synthesis with tabloid flair — what's trending, what it means, what's overblown.",
        status: "active",
        trigger: "source",
        schedule: nil,
        roster: [
          %{
            "who" => "journeyman",
            "preferred_who" => "the-tabloid",
            "when" => "on_trigger",
            "how" => "solo"
          }
        ],
        source_ids: [],
        output_type: "freeform",
        loop_mode: "reflect",
        loop_tools: ["query_lore"]
      },
      %{
        name: "Weekly Arts Roundup",
        description: "Weekly synthesis of culture and entertainment.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 10 * * 6",
        roster: [
          %{
            "who" => "apprentice",
            "preferred_who" => "the-historian",
            "when" => "on_trigger",
            "how" => "solo"
          }
        ],
        source_ids: [],
        output_type: "artifact",
        entry_title_template: "Arts Roundup — {date}",
        context_providers: [%{"type" => "lore", "limit" => 10}],
        loop_mode: "reflect",
        loop_tools: ["query_lore"]
      },
      %{
        name: "Deep Cut",
        description: "A lyrical, unexpected take on any cultural moment.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [
          %{
            "who" => "apprentice",
            "preferred_who" => "the-poet",
            "when" => "on_trigger",
            "how" => "solo"
          }
        ],
        source_ids: [],
        output_type: "freeform",
        loop_mode: "reflect",
        loop_tools: ["query_lore"]
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Culture Digest Loop",
        description: "Continuous culture intake and weekly arts synthesis",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "Culture Brief", "flow" => "always"},
          %{"quest_name" => "Weekly Arts Roundup", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
