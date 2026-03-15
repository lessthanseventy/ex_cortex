defmodule ExCortex.Pathways.MarketSignals do
  @moduledoc """
  Market Signals cluster pathway.

  Business and financial intelligence. Tracks market signals through daily
  synthesis and weekly pattern recognition. Uses builtin neurons: market-analyst,
  risk-assessor, trend-spotter, hype-detector.
  """

  alias ExCortex.Neurons.Builtin

  def metadata do
    neurons = [
      Builtin.get("market-analyst"),
      Builtin.get("risk-assessor"),
      Builtin.get("trend-spotter"),
      Builtin.get("hype-detector")
    ]

    %{
      banner: :business,
      name: "Market Signals",
      description:
        "Business and financial intelligence. Tracks market signals through daily synthesis and weekly pattern recognition.",
      roles: Enum.map(neurons, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    neurons = [
      {"market-analyst", :journeyman},
      {"risk-assessor", :journeyman},
      {"trend-spotter", :apprentice},
      {"hype-detector", :apprentice}
    ]

    Enum.flat_map(neurons, fn {member_id, rank} ->
      builtin = Builtin.get(member_id)

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
        name: "Daily Market Brief",
        description: "Daily business and financial synthesis from incoming sources.",
        status: "active",
        trigger: "source",
        schedule: nil,
        roster: [
          %{
            "who" => "journeyman",
            "preferred_who" => "market-analyst",
            "when" => "on_trigger",
            "how" => "solo"
          }
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Market Brief — {date}",
        loop_mode: "reflect",
        loop_tools: ["query_lore", "web_search", "web_fetch"]
      },
      %{
        name: "Weekly Market Roundup",
        description: "Weekly synthesis of market signals and emerging patterns.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 7 * * 1",
        roster: [
          %{
            "who" => "all",
            "when" => "on_trigger",
            "how" => "consensus"
          }
        ],
        source_ids: [],
        output_type: "artifact",
        context_providers: [%{"type" => "memory", "limit" => 10}],
        entry_title_template: "Market Roundup — {date}",
        loop_mode: "reflect",
        loop_tools: ["query_lore", "web_search", "web_fetch"]
      },
      %{
        name: "Risk Check",
        description: "Is this business news a real signal or noise?",
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
        output_type: "verdict",
        escalate: true,
        escalate_threshold: 0.6
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Market Digest Loop",
        description: "Continuous market news intake and weekly pattern synthesis",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"thought_name" => "Daily Market Brief", "flow" => "always"},
          %{"thought_name" => "Weekly Market Roundup", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
