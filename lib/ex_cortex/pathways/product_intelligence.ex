defmodule ExCortex.Pathways.ProductIntelligence do
  @moduledoc """
  Product intelligence cluster pathway.

  Uses builtin neurons: feedback-analyst, risk-assessor,
  trend-spotter, competitive-analyst.
  """

  alias ExCortex.Neurons.Builtin

  def metadata do
    neurons = [
      Builtin.get("feedback-analyst"),
      Builtin.get("risk-assessor"),
      Builtin.get("trend-spotter"),
      Builtin.get("competitive-analyst")
    ]

    %{
      lobe: :business,
      name: "Product Intelligence",
      description:
        "Product intelligence cluster — synthesizes user feedback, market trends, and competitive signals into actionable insight.",
      roles: Enum.map(neurons, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    neurons = [
      {"feedback-analyst", "Feedback Analyst"},
      {"risk-assessor", "Risk Assessor"},
      {"trend-spotter", "Trend Spotter"},
      {"competitive-analyst", "Competitive Analyst"}
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
        name: "Feedback Quick Scan",
        description: "Quick feedback scan triggered by incoming source data",
        status: "active",
        trigger: "source",
        schedule: nil,
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Product Intelligence Report",
        description: "Synthesize intelligence into a running product intelligence log",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "both",
        entry_title_template: "Product Intelligence",
        log_title_template: "Intelligence Log — {date}",
        context_providers: [
          %{"type" => "memory", "tags" => ["product", "feedback", "market"], "limit" => 5, "sort" => "top"}
        ],
        loop_mode: "reflect",
        loop_tools: ["query_memory", "web_search", "search_email"]
      },
      %{
        name: "Full Intelligence Review",
        description: "Full product intelligence review by all neurons reaching consensus",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      }
    ]
  end

  def rumination_definitions do
    [
      %{
        name: "Weekly Product Intelligence",
        description: "Weekly product intelligence synthesis campaign",
        status: "active",
        trigger: "scheduled",
        schedule: "@weekly",
        steps: [
          %{"thought_name" => "Feedback Quick Scan", "flow" => "always"},
          %{"thought_name" => "Full Intelligence Review", "flow" => "always"},
          %{"thought_name" => "Product Intelligence Report", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
