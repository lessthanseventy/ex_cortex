defmodule ExCortex.Pathways.Platform do
  @moduledoc """
  Backend, infrastructure, and platform reliability review cluster pathway.

  Uses builtin neurons: backend-reviewer, devops-reviewer,
  performance-auditor, security-skeptic.
  """

  alias ExCortex.Neurons.Builtin

  def metadata do
    neurons = [
      Builtin.get("backend-reviewer"),
      Builtin.get("devops-reviewer"),
      Builtin.get("performance-auditor"),
      Builtin.get("security-skeptic")
    ]

    %{
      banner: :tech,
      name: "Platform Cluster",
      description:
        "Backend, infrastructure, and platform reliability review cluster — evaluates architecture, deployment, and performance.",
      roles: Enum.map(neurons, fn m -> %{name: m.name, system_prompt: m.system_prompt} end),
      actions: [:pass, :warn, :fail],
      strategy: :majority,
      middleware: []
    }
  end

  def resource_definitions do
    neurons = [
      {"backend-reviewer", "Backend Reviewer"},
      {"devops-reviewer", "DevOps Reviewer"},
      {"performance-auditor", "Performance Auditor"},
      {"security-skeptic", "Security Skeptic"}
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
        name: "Platform Quick Scan",
        description: "Quick automated platform health scan by apprentice neurons",
        status: "active",
        trigger: "scheduled",
        schedule: "@hourly",
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Full Platform Review",
        description: "Comprehensive platform review by all neurons reaching consensus",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Platform Health Report",
        description: "Synthesize platform health findings into a running memory log",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "both",
        entry_title_template: "Platform Health",
        log_title_template: "Platform Log — {date}",
        context_providers: [
          %{"type" => "memory", "tags" => ["platform", "security", "performance"], "limit" => 5, "sort" => "top"}
        ],
        loop_mode: "reflect",
        loop_tools: ["query_memory", "search_github"]
      }
    ]
  end

  def thought_definitions do
    [
      %{
        name: "Platform Review Campaign",
        description: "Daily platform health review campaign",
        status: "active",
        trigger: "scheduled",
        schedule: "@daily",
        steps: [
          %{"thought_name" => "Platform Quick Scan", "flow" => "always"},
          %{"thought_name" => "Full Platform Review", "flow" => "on_flag"},
          %{"thought_name" => "Platform Health Report", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
