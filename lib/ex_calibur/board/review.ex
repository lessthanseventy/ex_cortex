defmodule ExCalibur.Board.Review do
  @moduledoc "Continuous review pipeline campaign templates."

  alias ExCalibur.Board

  def templates do
    [
      pr_review_pipeline(),
      url_change_review(),
      content_safety_webhook(),
      compliance_monitor()
    ]
  end

  defp pr_review_pipeline do
    %Board{
      id: "pr_review_pipeline",
      name: "PR Review Pipeline",
      category: :review,
      description:
        "Full PR review via GitHub webhook — quick scan on every PR, full consensus review for flagged ones, with a GitHub PR comment posted back.",
      suggested_team: "Code Review guild is ideal.",
      requires: [
        {:source_type, "webhook"},
        {:herald_type, "github_pr"}
      ],
      quest_definitions: [
        %{
          name: "PR Quick Scan",
          description: "Quick automated PR scan — does this need a full review?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
          source_ids: []
        },
        %{
          name: "PR Full Review",
          description: "Full consensus PR review — correctness, style, security, performance.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Post PR Review Comment",
          description: "Post the full review as a GitHub PR comment.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "github_pr",
          herald_name: "github_pr:default"
        }
      ],
      campaign_definition: %{
        name: "PR Review Pipeline Campaign",
        description: "Webhook-triggered PR review with GitHub comment for flagged PRs.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "PR Quick Scan", "flow" => "always"},
          %{"quest_name" => "PR Full Review", "flow" => "on_flag"},
          %{"quest_name" => "Post PR Review Comment", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp url_change_review do
    %Board{
      id: "url_change_review",
      name: "URL Change Monitor",
      category: :review,
      description:
        "Monitor URLs for content changes and assess their impact. Useful for tracking competitor sites, regulatory pages, or API documentation.",
      suggested_team: "Any guild with content or risk awareness.",
      requires: [
        {:source_type, "url"},
        {:herald_type, "slack"}
      ],
      quest_definitions: [
        %{
          name: "URL Change Quick Assessment",
          description: "Quick assessment of a detected URL change — is this significant?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
          source_ids: []
        },
        %{
          name: "URL Change Full Review",
          description:
            "Full review of a significant URL change — impact and recommended response.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Post URL Change Alert",
          description: "Post URL change assessment to team Slack.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "slack",
          herald_name: "slack:default"
        }
      ],
      campaign_definition: %{
        name: "URL Change Monitor Campaign",
        description: "URL change detection with Slack alert for significant changes.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "URL Change Quick Assessment", "flow" => "always"},
          %{"quest_name" => "URL Change Full Review", "flow" => "on_flag"},
          %{"quest_name" => "Post URL Change Alert", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp content_safety_webhook do
    %Board{
      id: "content_safety_webhook",
      name: "Content Safety Review",
      category: :review,
      description:
        "Review user-submitted content via webhook for safety violations. Quick automated scan with full review and Slack escalation for flagged content.",
      suggested_team: "Content Moderation guild is ideal.",
      requires: [
        {:source_type, "webhook"},
        {:herald_type, "slack"}
      ],
      quest_definitions: [
        %{
          name: "Content Safety Quick Scan",
          description: "Quick automated safety scan of submitted content.",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
          source_ids: []
        },
        %{
          name: "Content Safety Full Review",
          description: "Full consensus safety review of flagged content.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Escalate Content Violation",
          description: "Escalate confirmed content safety violation to team Slack.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "slack",
          herald_name: "slack:default"
        }
      ],
      campaign_definition: %{
        name: "Content Safety Campaign",
        description: "Webhook-triggered content safety review with Slack escalation.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "Content Safety Quick Scan", "flow" => "always"},
          %{"quest_name" => "Content Safety Full Review", "flow" => "on_flag"},
          %{"quest_name" => "Escalate Content Violation", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp compliance_monitor do
    %Board{
      id: "compliance_monitor",
      name: "Compliance Monitor",
      category: :review,
      description:
        "Continuous compliance monitoring from regulatory feeds. Hourly scan for changes to rules, advisories, or standards that affect your operations.",
      suggested_team: "Risk Assessment or Contract Review guild.",
      requires: [
        {:source_type, "feed"},
        {:herald_type, "slack"}
      ],
      quest_definitions: [
        %{
          name: "Compliance Feed Quick Scan",
          description:
            "Quick scan of incoming regulatory/compliance feed entry — does this affect us?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          context_providers: [
            %{
              "type" => "lore",
              "tags" => ["compliance", "risk"],
              "limit" => 3,
              "sort" => "importance"
            }
          ]
        },
        %{
          name: "Compliance Full Assessment",
          description:
            "Full assessment of a compliance signal — impact, required response, and timeline.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "Post Compliance Alert",
          description: "Post compliance finding and recommended action to team Slack.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          output_type: "slack",
          herald_name: "slack:default"
        }
      ],
      campaign_definition: %{
        name: "Compliance Monitor Campaign",
        description: "Feed-triggered compliance monitoring with Slack alerts.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"quest_name" => "Compliance Feed Quick Scan", "flow" => "always"},
          %{"quest_name" => "Compliance Full Assessment", "flow" => "on_flag"},
          %{"quest_name" => "Post Compliance Alert", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end
end
