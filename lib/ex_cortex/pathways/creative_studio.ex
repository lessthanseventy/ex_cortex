defmodule ExCortex.Pathways.CreativeStudio do
  @moduledoc """
  Creative and content review cluster pathway.

  Uses builtin neurons: the-poet, the-historian,
  the-tabloid, brand-guardian.
  """

  alias ExCortex.Neurons.Builtin

  def metadata do
    neurons = [
      Builtin.get("the-poet"),
      Builtin.get("the-historian"),
      Builtin.get("the-tabloid"),
      Builtin.get("brand-guardian")
    ]

    %{
      lobe: :limbic,
      name: "Creative Studio",
      description: "Creative and content review cluster — evaluates brand voice, tone, and messaging, with flair.",
      roles: Enum.map(neurons, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    neurons = [
      {"the-poet", "The Poet"},
      {"the-historian", "The Historian"},
      {"the-tabloid", "The Tabloid"},
      {"brand-guardian", "Brand Guardian"}
    ]

    Enum.flat_map(neurons, fn {neuron_id, _name} ->
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
            "rank" => "journeyman",
            "model" => builtin.ranks.journeyman.model,
            "strategy" => builtin.ranks.journeyman.strategy,
            "tools" => "all_safe"
          }
        }
      ]
    end)
  end

  def synapse_definitions do
    [
      %{
        name: "Brand Voice Check",
        description: "Brand voice consensus check by all neurons",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [
          %{
            "who" => "all",
            "preferred_who" => "brand-guardian",
            "when" => "on_trigger",
            "how" => "consensus"
          }
        ],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Chronicle Entry",
        description: "Record events as a chronicle entry in the historian's voice",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [
          %{
            "who" => "master",
            "preferred_who" => "the-historian",
            "when" => "on_trigger",
            "how" => "solo"
          }
        ],
        source_ids: [],
        output_type: "freeform",
        loop_mode: "reflect",
        loop_tools: ["query_memory", "search_obsidian", "read_obsidian"]
      },
      %{
        name: "Tone Review",
        description: "Quick tone review triggered by source content",
        status: "active",
        trigger: "source",
        schedule: nil,
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      }
    ]
  end

  def rumination_definitions do
    [
      %{
        name: "Content Review Campaign",
        description: "Manual content review — tone check then brand voice check on flag",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"thought_name" => "Tone Review", "flow" => "always"},
          %{"thought_name" => "Brand Voice Check", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    ]
  end
end
