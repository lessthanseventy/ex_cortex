defmodule ExCalibur.Charters.DependencyAudit do
  @moduledoc """
  Dependency audit pipeline charter.

  Installs VulnerabilityScanner + LicenseChecker + MaintenanceEvaluator roles,
  approve/warn/block/escalate actions, with role_veto consensus strategy.
  """

  def metadata do
    %{
      banner: :tech,
      name: "Dependency Audit",
      description: "Multi-agent dependency health and supply chain security pipeline",
      roles: [
        %{
          name: "vulnerability-scanner",
          system_prompt: """
          You are a dependency vulnerability scanner. Evaluate known CVEs, security
          advisories, and exploit availability for dependencies. Check transitive
          dependencies too. Consider severity, exploitability, and whether the
          vulnerable code path is actually used.

          Respond with:
          ACTION: approve | warn | block | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "thorough", model: "gemma3:4b", strategy: "cod"},
            %{name: "quick", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "license-checker",
          system_prompt: """
          You are a dependency license checker. Evaluate license compatibility:
          copyleft contamination, attribution requirements, commercial use restrictions,
          and patent clauses. Flag license changes between dependency versions.

          Respond with:
          ACTION: approve | warn | block | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "strict", model: "gemma3:4b", strategy: "cod"},
            %{name: "permissive", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "maintenance-evaluator",
          system_prompt: """
          You are a dependency maintenance evaluator. Assess project health: last commit
          date, open issue count, bus factor, release cadence, breaking change frequency,
          and deprecation status. Flag abandoned or at-risk dependencies.

          Respond with:
          ACTION: approve | warn | block | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "alpha", model: "gemma3:4b", strategy: "cod"},
            %{name: "beta", model: "phi4-mini", strategy: "cot"}
          ]
        }
      ],
      actions: [:approve, :warn, :block, :escalate],
      strategy: {:role_veto, veto_roles: [:vulnerability_scanner]},
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
        name: "Dependency Quick Scan",
        description: "Automated dependency scan triggered when dependency files change",
        status: "active",
        trigger: "source",
        schedule: nil,
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        context_providers: [%{"type" => "lore", "tags" => ["deps"], "limit" => 5, "sort" => "importance"}],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Full Dependency Audit",
        description: "Comprehensive dependency health review by all members reaching consensus",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Dependency Risk Register",
        description: """
        Synthesize the current dependency risk landscape into a living register. Include:
        known vulnerable packages with CVE references, license exceptions approved,
        packages flagged for replacement with migration notes, and supply chain concerns.
        This entry is the single source of truth for dependency health.
        """,
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "both",
        entry_title_template: "Dependency Risk Register",
        log_title_template: "Dependency Audit Log — {date}",
        context_providers: [%{"type" => "lore", "tags" => ["deps"], "limit" => 5, "sort" => "importance"}],
        loop_mode: "reflect",
        loop_tools: ["query_lore", "search_github", "web_search"]
      },
      %{
        name: "File Vulnerability Issue",
        description: "Open a GitHub issue for significant CVEs or supply chain risks found",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "github_issue",
        herald_name: "github_issue:default"
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Weekly Dependency Audit Campaign",
        description: "Automated scan that escalates to full audit on any findings",
        status: "active",
        trigger: "scheduled",
        schedule: "@weekly",
        steps: [
          %{"quest_name" => "Dependency Quick Scan", "flow" => "always"},
          %{"quest_name" => "Full Dependency Audit", "flow" => "on_flag"},
          %{"quest_name" => "File Vulnerability Issue", "flow" => "on_flag"},
          %{"quest_name" => "Dependency Risk Register", "flow" => "always"}
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
