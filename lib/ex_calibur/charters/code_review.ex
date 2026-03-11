defmodule ExCalibur.Charters.CodeReview do
  @moduledoc """
  Code review pipeline charter.

  Installs SecurityAnalyst + StyleReviewer + ArchitectureCritic roles,
  approve/request-changes/block actions, with role_veto consensus strategy.
  """

  def metadata do
    %{
      name: "Code Review",
      description: "Multi-agent code quality and security review pipeline",
      roles: [
        %{
          name: "security-analyst",
          system_prompt: """
          You are a security analyst reviewing code changes. Look for vulnerabilities
          including injection attacks, authentication flaws, data exposure,
          insecure defaults, and dependency risks.

          Respond with:
          ACTION: approve | request-changes | block | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "thorough", model: "gemma3:4b", strategy: "cod"},
            %{name: "quick", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "style-reviewer",
          system_prompt: """
          You are a code style reviewer. Evaluate code changes for readability,
          naming conventions, documentation, test coverage, and adherence
          to project coding standards.

          Respond with:
          ACTION: approve | request-changes | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "alpha", model: "gemma3:4b", strategy: "cod"},
            %{name: "beta", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "architecture-critic",
          system_prompt: """
          You are an architecture critic. Evaluate code changes for design patterns,
          separation of concerns, coupling, cohesion, and long-term maintainability.
          Flag breaking changes and architectural regressions.

          Respond with:
          ACTION: approve | request-changes | block | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "alpha", model: "gemma3:4b", strategy: "cod"},
            %{name: "beta", model: "phi4-mini", strategy: "cot"}
          ]
        }
      ],
      actions: [:approve, :"request-changes", :block],
      strategy: {:role_veto, veto_roles: [:security_analyst]},
      middleware: [
        "Excellence.Middleware.TelemetryMiddleware",
        "Excellence.Middleware.Cache",
        "Excellence.Middleware.Evaluate",
        "Excellence.Middleware.AuditLog"
      ]
    }
  end

  def quest_definitions do
    [
      %{
        name: "Code Quality Scan",
        description: "Quick automated code quality check by apprentice members",
        status: "active",
        trigger: "scheduled",
        schedule: "@hourly",
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        context_providers: [%{"type" => "lore", "tags" => ["code-review"], "limit" => 3, "sort" => "importance"}],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Full Code Review",
        description: "Comprehensive review by all members reaching consensus",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Code Pattern Memory",
        description: """
        Synthesize recurring code quality findings into institutional memory. Document:
        security anti-patterns that keep appearing, architectural debt items identified,
        modules or areas with consistent issues, and recently resolved patterns that
        improved the codebase. Focus on what would help a reviewer calibrate expectations
        for this specific codebase.
        """,
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "both",
        entry_title_template: "Code Patterns",
        log_title_template: "Code Review Log — {date}",
        context_providers: [%{"type" => "lore", "tags" => ["code-review"], "limit" => 5, "sort" => "importance"}],
        loop_mode: "reflect",
        loop_tools: ["query_lore"]
      },
      %{
        name: "File Code Review Issue",
        description: "Open a GitHub issue summarizing significant code quality findings",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "github_issue",
        herald_name: "github_issue:default"
      },
      %{
        name: "Post Code Review Summary",
        description: "Post a code review summary to the team Slack channel",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "slack",
        herald_name: "slack:default"
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Daily Code Review Campaign",
        description: "Automated scan that escalates to full review on any findings",
        status: "active",
        trigger: "scheduled",
        schedule: "@daily",
        steps: [
          %{"quest_name" => "Code Quality Scan", "flow" => "always"},
          %{"quest_name" => "Full Code Review", "flow" => "on_flag"},
          %{"quest_name" => "File Code Review Issue", "flow" => "on_flag"},
          %{"quest_name" => "Post Code Review Summary", "flow" => "on_flag"},
          %{"quest_name" => "Code Pattern Memory", "flow" => "always"}
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
