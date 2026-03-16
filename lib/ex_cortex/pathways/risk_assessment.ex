defmodule ExCortex.Pathways.RiskAssessment do
  @moduledoc """
  Risk assessment pipeline pathway.

  Installs RiskScorer + ComplianceChecker + FraudDetector roles,
  approve/flag/reject actions, with weighted consensus strategy.
  """

  def metadata do
    %{
      lobe: :business,
      name: "Risk Assessment",
      description: "Multi-agent risk scoring and fraud detection pipeline",
      roles: [
        %{
          name: "risk-scorer",
          system_prompt: """
          You are a risk scorer. Evaluate the input for financial, operational,
          and reputational risk. Consider probability of adverse outcomes,
          potential impact severity, and risk mitigation factors.

          Respond with:
          ACTION: approve | flag | reject | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "conservative", model: "gemma3:4b", strategy: "cod"},
            %{name: "balanced", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "compliance-checker",
          system_prompt: """
          You are a compliance checker. Evaluate the input against regulatory
          requirements, industry standards, and internal policies. Flag
          any potential compliance violations or regulatory risks.

          Respond with:
          ACTION: approve | flag | reject | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "alpha", model: "gemma3:4b", strategy: "cod"},
            %{name: "beta", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "fraud-detector",
          system_prompt: """
          You are a fraud detector. Analyze the input for signs of fraudulent
          activity, suspicious patterns, identity misrepresentation, and
          known fraud indicators.

          Respond with:
          ACTION: approve | flag | reject | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "alpha", model: "gemma3:4b", strategy: "cod"},
            %{name: "beta", model: "phi4-mini", strategy: "cot"}
          ]
        }
      ],
      actions: [:approve, :flag, :reject],
      strategy: {:weighted, weights: %{risk_scorer: 1.5, compliance_checker: 1.2, fraud_detector: 1.0}}
    }
  end

  def synapse_definitions do
    [
      %{
        name: "Risk Quick Scan",
        description: "Quick automated risk scan by apprentice neurons",
        status: "active",
        trigger: "scheduled",
        schedule: "@hourly",
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        context_providers: [%{"type" => "memory", "tags" => ["risk"], "limit" => 3, "sort" => "importance"}],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Full Risk Assessment",
        description: "Comprehensive risk analysis by all neurons reaching consensus",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Risk Pattern Memory",
        description: """
        Synthesize current risk patterns and fraud signals into a single up-to-date entry.
        Include: active high-risk patterns seen recently, confirmed fraud signals,
        risk score calibration notes (what scored high but was fine, what scored low but
        was problematic), and any resolved compliance edge cases. Replace the previous
        entry — this should always reflect the current threat landscape.
        """,
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "replace",
        entry_title_template: "Risk Patterns — Current",
        log_title_template: nil,
        context_providers: [%{"type" => "memory", "tags" => ["risk"], "limit" => 5, "sort" => "importance"}],
        loop_mode: "reflect",
        loop_tools: ["query_memory", "web_search"]
      },
      %{
        name: "Page On High Risk",
        description: "Trigger a PagerDuty incident when a high-risk assessment warrants immediate response",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "pagerduty",
        expression_name: "pagerduty:default"
      },
      %{
        name: "Post Risk Summary",
        description: "Post a risk assessment summary to the team Slack channel",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "slack",
        expression_name: "slack:default"
      }
    ]
  end

  def rumination_definitions do
    [
      %{
        name: "Risk Assessment Campaign",
        description: "Automated scan that escalates to full assessment on any flagged risks",
        status: "active",
        trigger: "scheduled",
        schedule: "@daily",
        steps: [
          %{"thought_name" => "Risk Quick Scan", "flow" => "always"},
          %{"thought_name" => "Full Risk Assessment", "flow" => "on_flag"},
          %{"thought_name" => "Page On High Risk", "flow" => "on_flag"},
          %{"thought_name" => "Post Risk Summary", "flow" => "on_flag"},
          %{"thought_name" => "Risk Pattern Memory", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end

  def resource_definitions do
    meta = metadata()

    Enum.flat_map(meta.roles, fn role ->
      role.perspectives
      |> Enum.with_index()
      |> Enum.map(fn {perspective, idx} ->
        %{
          type: "role",
          name: role.name,
          status: "active",
          source: "db",
          config: %{
            "system_prompt" => role.system_prompt,
            "rank" => Enum.at(["apprentice", "journeyman", "master"], idx, "master"),
            "model" => perspective.model,
            "strategy" => perspective.strategy,
            "tools" => "all_safe"
          }
        }
      end)
    end)
  end
end
