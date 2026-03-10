defmodule ExCalibur.Charters.TechDispatch do
  @moduledoc """
  Tech Dispatch guild charter.

  Daily and weekly technology news synthesis. Learns trends over time
  through accumulated lore. Uses builtin members: news-correspondent,
  trend-spotter, hype-detector, the-historian.
  """

  alias ExCalibur.Members.BuiltinMember

  def metadata do
    members = [
      BuiltinMember.get("news-correspondent"),
      BuiltinMember.get("trend-spotter"),
      BuiltinMember.get("hype-detector"),
      BuiltinMember.get("the-historian")
    ]

    %{
      name: "Tech Dispatch",
      description: "Daily and weekly technology news synthesis. Learns trends over time through accumulated lore.",
      roles: Enum.map(members, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    members = [
      {"news-correspondent", :journeyman},
      {"trend-spotter", :journeyman},
      {"hype-detector", :apprentice},
      {"the-historian", :journeyman}
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
        name: "Daily Tech Brief",
        description: "Synthesizes incoming tech articles into a clean daily briefing stored as lore.",
        status: "active",
        trigger: "source",
        schedule: nil,
        roster: [
          %{
            "who" => "journeyman",
            "preferred_who" => "news-correspondent",
            "when" => "on_trigger",
            "how" => "solo"
          }
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Tech Brief — {date}"
      },
      %{
        name: "Weekly Tech Trends",
        description: "Synthesizes the week's lore into trend patterns.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 8 * * 1",
        roster: [
          %{
            "who" => "journeyman",
            "preferred_who" => "trend-spotter",
            "when" => "on_trigger",
            "how" => "solo"
          }
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Weekly Tech Trends — {date}",
        context_providers: [%{"type" => "lore", "limit" => 30}]
      },
      %{
        name: "Hype Check",
        description: "Is this tech story real or hype? Submit a claim for evaluation.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [
          %{
            "who" => "all",
            "when" => "on_trigger",
            "how" => "consensus"
          }
        ],
        source_ids: [],
        output_type: "verdict"
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Tech Digest Loop",
        description: "Continuous tech news intake and weekly trend synthesis",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "Daily Tech Brief", "flow" => "always"},
          %{"quest_name" => "Weekly Tech Trends", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
