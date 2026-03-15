defmodule ExCortex.Board.Triage do
  @moduledoc "Source-triggered triage thought templates."

  alias ExCortex.Board

  def templates do
    [
      jira_ticket_triage(),
      github_issue_triage(),
      error_monitor(),
      feed_threat_triage(),
      feedback_triage()
    ]
  end

  defp jira_ticket_triage do
    %Board{
      id: "jira_ticket_triage",
      banner: :tech,
      name: "Jira Ticket Triage",
      category: :triage,
      description:
        "Automatically triage incoming Jira tickets by severity, route urgent ones for full review, and post a Slack summary. Runs whenever new ticket data arrives.",
      suggested_team:
        "Works with any cluster. The Incident Triage cluster (ImpactAssessor + RootCauseAnalyst + EscalationRouter) is a natural fit.",
      requires: [
        {:source_type, "webhook"},
        {:expression_type, "slack"}
      ],
      step_definitions: [
        %{
          name: "Jira Quick Triage",
          description: "Quick triage of incoming Jira ticket — assess urgency and route for full review if warranted.",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [
            %{
              "who" => "apprentice",
              "preferred_who" => "impact-assessor",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: []
        },
        %{
          name: "Jira Full Assessment",
          description: "Full consensus assessment of a Jira ticket — severity, root cause, and recommended response.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{"who" => "all", "when" => "on_trigger", "how" => "consensus"}
          ],
          source_ids: []
        },
        %{
          name: "Jira Slack Alert",
          description: "Post a concise Jira ticket summary and recommended action to the team Slack channel.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{
              "who" => "master",
              "preferred_who" => "escalation-router",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "slack",
          expression_name: "slack:default"
        }
      ],
      rumination_definition: %{
        name: "Jira Ticket Triage Thought",
        description: "Source-triggered triage that escalates high-severity Jira tickets to Slack.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "Jira Quick Triage", "flow" => "always"},
          %{"step_name" => "Jira Full Assessment", "flow" => "on_flag"},
          %{"step_name" => "Jira Slack Alert", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp github_issue_triage do
    %Board{
      id: "github_issue_triage",
      banner: :tech,
      name: "GitHub Issue Triage",
      category: :triage,
      description:
        "Triage incoming GitHub issues via webhook — assess severity and file a tracked issue response for confirmed bugs or blockers.",
      suggested_team: "Code Review cluster works well. Any cluster with code-aware neurons will do.",
      requires: [
        {:source_type, "webhook"},
        {:expression_type, "github_issue"}
      ],
      step_definitions: [
        %{
          name: "GitHub Issue Quick Scan",
          description: "Quick triage of a GitHub issue — is it a confirmed bug, feature request, or noise?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
          source_ids: []
        },
        %{
          name: "GitHub Issue Full Review",
          description: "Full consensus review of a GitHub issue — priority, label suggestions, and response.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "File GitHub Issue Response",
          description: "File a tracked GitHub issue with assessment and recommended action.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "github_issue",
          expression_name: "github_issue:default"
        }
      ],
      rumination_definition: %{
        name: "GitHub Issue Triage Thought",
        description: "Webhook-triggered triage that files tracked responses for confirmed bugs.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "GitHub Issue Quick Scan", "flow" => "always"},
          %{"step_name" => "GitHub Issue Full Review", "flow" => "on_flag"},
          %{"step_name" => "File GitHub Issue Response", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp error_monitor do
    %Board{
      id: "error_monitor",
      banner: :tech,
      name: "Error Monitor & Page",
      category: :triage,
      description:
        "Stream errors from a log aggregator or error tracker, triage severity, and page on-call for critical incidents.",
      suggested_team: "Incident Triage cluster (ImpactAssessor + RootCauseAnalyst + EscalationRouter) is the ideal fit.",
      requires: [
        {:source_type, "websocket"},
        {:expression_type, "pagerduty"}
      ],
      step_definitions: [
        %{
          name: "Error Stream Quick Scan",
          description: "Quick scan of incoming error stream data — is this page-worthy?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [
            %{
              "who" => "apprentice",
              "preferred_who" => "impact-assessor",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: []
        },
        %{
          name: "Error Full Triage",
          description: "Full incident triage — severity, root cause, and page decision.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Page On-Call Engineer",
          description: "Page on-call via PagerDuty when the error warrants immediate response.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{
              "who" => "master",
              "preferred_who" => "escalation-router",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: [],
          output_type: "pagerduty",
          expression_name: "pagerduty:default"
        }
      ],
      rumination_definition: %{
        name: "Error Monitor Thought",
        description: "Real-time error stream triage with PagerDuty escalation for critical issues.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "Error Stream Quick Scan", "flow" => "always"},
          %{"step_name" => "Error Full Triage", "flow" => "on_flag"},
          %{"step_name" => "Page On-Call Engineer", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp feedback_triage do
    %Board{
      id: "feedback_triage",
      banner: :tech,
      name: "Feedback Triage",
      category: :triage,
      description:
        "Triage incoming user feedback from webhooks — quick bias and quality scan, full synthesis for high-signal items, Slack alert for urgent findings.",
      suggested_team: "Product Intelligence cluster. Any cluster with analyst neurons works.",
      requires: [
        {:source_type, "webhook"},
        {:expression_type, "slack"}
      ],
      step_definitions: [
        %{
          name: "Feedback Quick Scan",
          description: "Quick bias and quality scan of incoming feedback — is this high-signal or noise?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [
            %{
              "who" => "apprentice",
              "preferred_who" => "feedback-analyst",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: []
        },
        %{
          name: "Feedback Full Synthesis",
          description: "Full consensus feedback synthesis — themes, significance, and recommended action.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{"who" => "all", "when" => "on_trigger", "how" => "consensus"}
          ],
          source_ids: []
        },
        %{
          name: "Post Feedback Alert",
          description: "Post urgent feedback findings to team Slack.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{"who" => "master", "when" => "on_trigger", "how" => "solo"}
          ],
          source_ids: [],
          output_type: "slack",
          expression_name: "slack:default"
        }
      ],
      rumination_definition: %{
        name: "Feedback Triage Thought",
        description: "Source-triggered feedback triage with Slack alert for high-signal items.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "Feedback Quick Scan", "flow" => "always"},
          %{"step_name" => "Feedback Full Synthesis", "flow" => "on_flag"},
          %{"step_name" => "Post Feedback Alert", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp feed_threat_triage do
    %Board{
      id: "feed_threat_triage",
      banner: :tech,
      name: "Threat Feed Monitor",
      category: :triage,
      description:
        "Monitor industry threat intelligence feeds for signals relevant to your stack. Escalates findings to Slack.",
      suggested_team: "Risk Assessment cluster (RiskScorer + ComplianceChecker + FraudDetector) is ideal.",
      requires: [
        {:source_type, "feed"},
        {:expression_type, "slack"}
      ],
      step_definitions: [
        %{
          name: "Threat Feed Quick Scan",
          description: "Quick scan of incoming threat feed entries — is this relevant to our stack?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
          source_ids: []
        },
        %{
          name: "Threat Full Assessment",
          description: "Full consensus assessment of threat signal — risk level and recommended response.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Post Threat Alert",
          description: "Post threat assessment and recommended action to team Slack channel.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "slack",
          expression_name: "slack:default"
        }
      ],
      rumination_definition: %{
        name: "Threat Feed Monitor Thought",
        description: "Feed-triggered threat intelligence triage with Slack escalation.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "Threat Feed Quick Scan", "flow" => "always"},
          %{"step_name" => "Threat Full Assessment", "flow" => "on_flag"},
          %{"step_name" => "Post Threat Alert", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end
end
