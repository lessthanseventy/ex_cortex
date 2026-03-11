defmodule ExCalibur.Charters.IncidentTriage do
  @moduledoc """
  Incident triage pipeline charter.

  Installs ImpactAssessor + RootCauseAnalyst + EscalationRouter roles,
  monitor/alert/page/escalate actions, with role_veto consensus strategy.
  """

  def metadata do
    %{
      banner: :tech,
      name: "Incident Triage",
      description: "Multi-agent incident severity assessment and response routing pipeline",
      roles: [
        %{
          name: "impact-assessor",
          system_prompt: """
          You are an incident impact assessor. Evaluate blast radius: how many users
          are affected, which systems are impacted, revenue implications, and data
          integrity risks. Distinguish between degraded service and full outage.

          Respond with:
          ACTION: monitor | alert | page | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "conservative", model: "gemma3:4b", strategy: "cod"},
            %{name: "measured", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "root-cause-analyst",
          system_prompt: """
          You are a root cause analyst. Analyze incident symptoms to identify likely
          root cause categories: infrastructure failure, bad deployment, dependency
          outage, data corruption, traffic spike, or security breach. Look for
          correlating signals across systems.

          Respond with:
          ACTION: monitor | alert | page | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "alpha", model: "gemma3:4b", strategy: "cod"},
            %{name: "beta", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "escalation-router",
          system_prompt: """
          You are an escalation router. Determine urgency and routing: monitor quietly,
          alert the team channel, page on-call, or escalate to leadership. Consider
          time of day, blast radius, customer impact, and whether self-healing is likely.

          Respond with:
          ACTION: monitor | alert | page | escalate | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "alpha", model: "gemma3:4b", strategy: "cod"},
            %{name: "beta", model: "phi4-mini", strategy: "cot"}
          ]
        }
      ],
      actions: [:monitor, :alert, :page, :escalate],
      strategy: {:role_veto, veto_roles: [:impact_assessor]},
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
        name: "Incident Quick Triage",
        description: "Quick automated incident severity assessment by apprentice members",
        status: "active",
        trigger: "scheduled",
        schedule: "@hourly",
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        context_providers: [
          %{"type" => "quest_history", "limit" => 5},
          %{"type" => "lore", "tags" => ["incidents"], "limit" => 3, "sort" => "newest"}
        ],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Full Incident Analysis",
        description: "Comprehensive incident triage by all members reaching consensus",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Incident Pattern Memory",
        description: """
        Synthesize incident patterns and response learnings into the incident log.
        Document: the incident type, root cause, severity, response taken, and what
        was learned. This entry is appended each time — the accumulated history is what
        gives future triagers context to make faster, better-calibrated decisions.
        """,
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "append",
        entry_title_template: "Incident Report — {date}",
        log_title_template: nil,
        context_providers: [%{"type" => "lore", "tags" => ["incidents"], "limit" => 10, "sort" => "newest"}],
        loop_mode: "reflect",
        loop_tools: ["query_lore"]
      },
      %{
        name: "Page On-Call",
        description: "Page on-call via PagerDuty when the incident assessment warrants it",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "pagerduty",
        herald_name: "pagerduty:default"
      },
      %{
        name: "Post Incident Summary",
        description: "Post a concise incident summary to the team Slack channel",
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
        name: "Incident Response Campaign",
        description: "Automated triage that escalates to full analysis on any alerts",
        status: "active",
        trigger: "scheduled",
        schedule: "@hourly",
        steps: [
          %{"quest_name" => "Incident Quick Triage", "flow" => "always"},
          %{"quest_name" => "Full Incident Analysis", "flow" => "on_flag"},
          %{"quest_name" => "Page On-Call", "flow" => "on_flag"},
          %{"quest_name" => "Post Incident Summary", "flow" => "on_flag"},
          %{"quest_name" => "Incident Pattern Memory", "flow" => "always"}
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
