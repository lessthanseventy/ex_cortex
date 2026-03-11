defmodule ExCalibur.Charters.AccessibilityReview do
  @moduledoc """
  Accessibility review pipeline charter.

  Installs WcagAuditor + UsabilityReviewer + AssistiveTechAnalyst roles,
  pass/warn/fail/escalate actions, with role_veto consensus strategy.
  """

  def metadata do
    %{
      name: "Accessibility Review",
      description: "Multi-agent accessibility compliance and usability review pipeline",
      roles: [
        %{
          name: "wcag-auditor",
          system_prompt: """
          You are a WCAG accessibility auditor. Evaluate content against WCAG 2.1/2.2
          success criteria. Check semantic HTML, ARIA usage, color contrast ratios,
          keyboard navigation, and focus management. Reference specific WCAG criteria
          (e.g., 1.4.3 Contrast Minimum, 2.1.1 Keyboard) in your reasoning.

          Respond with:
          ACTION: pass | warn | fail | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "strict", model: "gemma3:4b", strategy: "cod"},
            %{name: "practical", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "usability-reviewer",
          system_prompt: """
          You are a usability reviewer focused on inclusive design. Evaluate screen reader
          flow and reading order, cognitive load, error recovery and messaging, form
          labeling, and touch target sizing. Consider users with diverse abilities.

          Respond with:
          ACTION: pass | warn | fail | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "alpha", model: "gemma3:4b", strategy: "cod"},
            %{name: "beta", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "assistive-tech-analyst",
          system_prompt: """
          You are an assistive technology compatibility analyst. Evaluate content for
          compatibility with screen readers (NVDA, JAWS, VoiceOver), voice control
          (Dragon, Voice Control), switch devices, and screen magnification. Flag
          patterns known to break specific assistive technologies.

          Respond with:
          ACTION: pass | warn | fail | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "alpha", model: "gemma3:4b", strategy: "cod"},
            %{name: "beta", model: "phi4-mini", strategy: "cot"}
          ]
        }
      ],
      actions: [:pass, :warn, :fail, :escalate],
      strategy: {:role_veto, veto_roles: [:wcag_auditor]},
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
        name: "WCAG Hourly Scan",
        description: "Quick automated accessibility check by apprentice members",
        status: "active",
        trigger: "scheduled",
        schedule: "@hourly",
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        context_providers: [%{"type" => "lore", "tags" => ["a11y"], "limit" => 3, "sort" => "importance"}],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Full Accessibility Audit",
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
        name: "A11y Knowledge Synthesis",
        description: """
        Synthesize key accessibility findings into a knowledge entry. Identify what a future
        auditor should remember: chronic failures by component, WCAG criteria that keep
        surfacing, recently fixed patterns, and notable regressions. Be specific and
        actionable — "form labels are consistently missing" beats "some issues found".
        """,
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "both",
        entry_title_template: "A11y Knowledge",
        log_title_template: "A11y Log — {date}",
        context_providers: [%{"type" => "lore", "tags" => ["a11y"], "limit" => 5, "sort" => "importance"}],
        loop_mode: "reflect",
        loop_tools: ["query_lore"]
      },
      %{
        name: "Post A11y Alert",
        description: "Post accessibility findings to the team Slack channel",
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
        name: "Monthly Accessibility Review",
        description: "Automated scan that escalates to full audit on any findings, then synthesizes knowledge",
        status: "active",
        trigger: "scheduled",
        schedule: "@monthly",
        steps: [
          %{"quest_name" => "WCAG Hourly Scan", "flow" => "always"},
          %{"quest_name" => "Full Accessibility Audit", "flow" => "on_flag"},
          %{"quest_name" => "Post A11y Alert", "flow" => "on_flag"},
          %{"quest_name" => "A11y Knowledge Synthesis", "flow" => "always"}
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
