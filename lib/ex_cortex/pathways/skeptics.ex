defmodule ExCortex.Pathways.Skeptics do
  @moduledoc """
  Pure skepticism cluster pathway.

  Uses builtin neurons: devils-advocate, challenger,
  evidence-collector, hype-detector.
  """

  alias ExCortex.Neurons.Builtin

  def metadata do
    neurons = [
      Builtin.get("devils-advocate"),
      Builtin.get("challenger"),
      Builtin.get("evidence-collector"),
      Builtin.get("hype-detector")
    ]

    %{
      banner: :tech,
      name: "The Skeptics",
      description:
        "Pure skepticism cluster — challenges every claim, demands evidence, and deflates hype before it ships.",
      roles: Enum.map(neurons, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    neurons = [
      {"devils-advocate", "Devil's Advocate"},
      {"challenger", "Challenger"},
      {"evidence-collector", "Evidence Collector"},
      {"hype-detector", "Hype Detector"}
    ]

    Enum.flat_map(neurons, fn {member_id, _name} ->
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
        description: "Full skeptic panel — all neurons reach consensus",
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
          %{"type" => "memory", "tags" => ["decisions", "findings"], "limit" => 5, "sort" => "importance"}
        ],
        loop_mode: "reflect",
        loop_tools: ["query_lore", "web_search", "search_obsidian"]
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
          %{"thought_name" => "Quick Challenge", "flow" => "always"},
          %{"thought_name" => "Full Skeptic Panel", "flow" => "on_flag"},
          %{"thought_name" => "Skeptic Findings", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
