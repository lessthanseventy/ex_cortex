defmodule ExCortex.Pathways.SportsCorner do
  @moduledoc """
  Sports Corner cluster pathway.

  Daily sports digest — scores, storylines, and what it all means.
  Builds a narrative arc over time. Uses builtin neurons: sports-anchor,
  the-historian, the-optimist.
  """

  alias ExCortex.Neurons.Builtin

  def metadata do
    neurons = [
      Builtin.get("sports-anchor"),
      Builtin.get("the-historian"),
      Builtin.get("the-optimist")
    ]

    %{
      banner: :lifestyle,
      name: "Sports Corner",
      description: "Daily sports digest — scores, storylines, and what it all means. Builds a narrative arc over time.",
      roles: Enum.map(neurons, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    neurons = [
      {"sports-anchor", :journeyman},
      {"the-historian", :apprentice},
      {"the-optimist", :apprentice}
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
        name: "Daily Sports Digest",
        description: "Daily sports brief: scores, highlights, best storyline.",
        status: "active",
        trigger: "source",
        schedule: nil,
        roster: [
          %{
            "who" => "journeyman",
            "preferred_who" => "sports-anchor",
            "when" => "on_trigger",
            "how" => "solo"
          }
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Sports — {date}",
        loop_mode: "reflect",
        loop_tools: ["query_memory", "web_search", "web_fetch", "describe_image"]
      },
      %{
        name: "Weekend Roundup",
        description: "End-of-week narrative synthesis from the week's sports memory.",
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
        entry_title_template: "Weekend Roundup — {date}",
        context_providers: [%{"type" => "memory", "limit" => 10}],
        loop_mode: "reflect",
        loop_tools: ["query_memory", "web_search", "web_fetch", "describe_image"]
      }
    ]
  end

  def thought_definitions do
    [
      %{
        name: "Sports Digest Loop",
        description: "Continuous sports news intake and weekend narrative synthesis",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"thought_name" => "Daily Sports Digest", "flow" => "always"},
          %{"thought_name" => "Weekend Roundup", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
