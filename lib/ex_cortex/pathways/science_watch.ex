defmodule ExCortex.Pathways.ScienceWatch do
  @moduledoc """
  Science Watch cluster pathway.

  Research and discovery synthesis. Translates science into plain language,
  separates signal from hype. Uses builtin neurons: science-correspondent,
  hype-detector, evidence-collector, the-historian.
  """

  alias ExCortex.Neurons.Builtin

  def metadata do
    neurons = [
      Builtin.get("science-correspondent"),
      Builtin.get("hype-detector"),
      Builtin.get("evidence-collector"),
      Builtin.get("the-historian")
    ]

    %{
      lobe: :lifestyle,
      name: "Science Watch",
      description:
        "Research and discovery synthesis. Translates science into plain language, separates signal from hype.",
      roles: Enum.map(neurons, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    neurons = [
      {"science-correspondent", :journeyman},
      {"hype-detector", :journeyman},
      {"evidence-collector", :journeyman},
      {"the-historian", :apprentice}
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
        name: "Daily Science Brief",
        description: "Plain-language synthesis of research and science news.",
        status: "active",
        trigger: "source",
        schedule: nil,
        roster: [
          %{
            "who" => "journeyman",
            "preferred_who" => "science-correspondent",
            "when" => "on_trigger",
            "how" => "solo"
          }
        ],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Science Brief — {date}",
        loop_mode: "reflect",
        loop_tools: ["query_memory", "web_search", "web_fetch", "read_pdf"]
      },
      %{
        name: "Hype Check",
        description: "Is this scientific claim solid? Evidence evaluation.",
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
      },
      %{
        name: "Weekly Research Roundup",
        description: "Weekly synthesis of scientific developments.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 9 * * 1",
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
        entry_title_template: "Research Roundup — {date}",
        context_providers: [%{"type" => "memory", "limit" => 20}],
        loop_mode: "reflect",
        loop_tools: ["query_memory", "web_search", "web_fetch", "read_pdf"]
      }
    ]
  end

  def rumination_definitions do
    [
      %{
        name: "Science Digest Loop",
        description: "Continuous science news intake and weekly research synthesis",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"thought_name" => "Daily Science Brief", "flow" => "always"},
          %{"thought_name" => "Weekly Research Roundup", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
