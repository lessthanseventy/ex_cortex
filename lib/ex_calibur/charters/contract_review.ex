defmodule ExCalibur.Charters.ContractReview do
  @moduledoc """
  Contract review pipeline charter.

  Installs RiskEvaluator + ObligationTracker + AmbiguityDetector roles,
  accept/flag/reject/escalate actions, with majority consensus strategy.
  """

  def metadata do
    %{
      banner: :business,
      name: "Contract Review",
      description: "Multi-agent document risk analysis and obligation tracking pipeline",
      roles: [
        %{
          name: "risk-evaluator",
          system_prompt: """
          You are a contract risk evaluator. Evaluate legal and financial exposure
          including liability clauses, indemnification terms, limitation of liability,
          termination penalties, and IP assignment. Flag one-sided or unusual terms
          that deviate from market standards.

          Respond with:
          ACTION: accept | flag | reject | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "conservative", model: "gemma3:4b", strategy: "cod"},
            %{name: "pragmatic", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "obligation-tracker",
          system_prompt: """
          You are a contract obligation tracker. Identify all commitments and deadlines:
          deliverables, SLAs, payment terms, renewal dates, notice periods, and
          reporting requirements. Surface everything you would need to actually do
          if you signed this contract.

          Respond with:
          ACTION: accept | flag | reject | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "alpha", model: "gemma3:4b", strategy: "cod"},
            %{name: "beta", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "ambiguity-detector",
          system_prompt: """
          You are a contract ambiguity detector. Find vague, contradictory, or missing
          terms: undefined key terms, conflicting clauses, implicit assumptions, and
          missing standard protections such as force majeure, dispute resolution,
          and governing law provisions.

          Respond with:
          ACTION: accept | flag | reject | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "alpha", model: "gemma3:4b", strategy: "cod"},
            %{name: "beta", model: "phi4-mini", strategy: "cot"}
          ]
        }
      ],
      actions: [:accept, :flag, :reject, :escalate],
      strategy: :majority,
      middleware: [
        "Excellence.Middleware.TelemetryMiddleware",
        "Excellence.Middleware.Evaluate",
        "Excellence.Middleware.AuditLog",
        "Excellence.Middleware.Notify"
      ]
    }
  end

  def quest_definitions do
    [
      %{
        name: "Contract Risk Scan",
        description: "Quick automated contract risk analysis by apprentice members",
        status: "active",
        trigger: "scheduled",
        schedule: "@hourly",
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        context_providers: [
          %{"type" => "member_stats"},
          %{"type" => "lore", "tags" => ["contracts"], "limit" => 3, "sort" => "importance"}
        ],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Full Contract Review",
        description: "Comprehensive contract analysis by all members reaching consensus",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Contract Knowledge Memory",
        description: """
        Synthesize contract review learnings into institutional memory. Document:
        standard clauses that routinely get flagged and the standing reasoning,
        known risky vendors and why, obligation items being actively tracked,
        and ambiguity patterns that have caused issues in the past. This entry gives
        every new contract review the benefit of institutional experience.
        """,
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "both",
        entry_title_template: "Contract Knowledge",
        log_title_template: "Contract Review Log — {date}",
        context_providers: [%{"type" => "lore", "tags" => ["contracts"], "limit" => 5, "sort" => "importance"}],
        loop_mode: "reflect",
        loop_tools: ["query_lore"]
      },
      %{
        name: "Email Contract Risk Summary",
        description: "Send a contract risk summary to stakeholders via email",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "email",
        herald_name: "email:default"
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Contract Review Campaign",
        description: "Automated scan that escalates to full review on any flagged risks",
        status: "active",
        trigger: "scheduled",
        schedule: "@daily",
        steps: [
          %{"quest_name" => "Contract Risk Scan", "flow" => "always"},
          %{"quest_name" => "Full Contract Review", "flow" => "on_flag"},
          %{"quest_name" => "Email Contract Risk Summary", "flow" => "on_flag"},
          %{"quest_name" => "Contract Knowledge Memory", "flow" => "always"}
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
