defmodule ExCortex.Pathways.TechDispatch do
  @moduledoc """
  Tech Dispatch cluster pathway.

  Daily and weekly technology news synthesis. Learns trends over time
  through accumulated memory. Uses builtin neurons: news-correspondent,
  trend-spotter, hype-detector, the-historian.
  """

  alias ExCortex.Neurons.Builtin

  def metadata do
    neurons = [
      Builtin.get("news-correspondent"),
      Builtin.get("trend-spotter"),
      Builtin.get("hype-detector"),
      Builtin.get("the-historian")
    ]

    %{
      banner: :tech,
      name: "Tech Dispatch",
      description: "Daily and weekly technology news synthesis. Learns trends over time through accumulated memory.",
      roles: Enum.map(neurons, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    neurons = [
      {"news-correspondent", :journeyman},
      {"trend-spotter", :journeyman},
      {"hype-detector", :apprentice},
      {"the-historian", :journeyman}
    ]

    Enum.flat_map(neurons, fn {neuron_id, rank} ->
      builtin = Builtin.get(neuron_id)

      [
        %{
          type: "role",
          name: builtin.name,
          status: "active",
          source: "db",
          config: %{
            "neuron_id" => neuron_id,
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
            "neuron_id" => neuron_id,
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

  def synapse_definitions do
    [
      %{
        name: "Daily Tech Brief",
        description: "Synthesizes incoming tech articles into a clean daily briefing stored as memory.",
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
        entry_title_template: "Tech Brief — {date}",
        loop_mode: "reflect",
        loop_tools: ["query_memory", "web_search", "search_obsidian"]
      },
      %{
        name: "Weekly Tech Trends",
        description: "Synthesizes the week's memory into trend patterns.",
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
        context_providers: [%{"type" => "memory", "limit" => 30}],
        loop_mode: "reflect",
        loop_tools: ["query_memory", "web_search", "search_obsidian"]
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
        output_type: "verdict",
        escalate: true,
        escalate_threshold: 0.6
      }
    ]
  end

  def thought_definitions do
    [
      %{
        name: "Tech Digest Loop",
        description: "Continuous tech news intake and weekly trend synthesis",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"thought_name" => "Daily Tech Brief", "flow" => "always"},
          %{"thought_name" => "Weekly Tech Trends", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
