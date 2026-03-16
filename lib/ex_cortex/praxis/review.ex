defmodule ExCortex.Praxis.Review do
  @moduledoc "Continuous review pipeline thought templates."

  alias ExCortex.Praxis

  def templates do
    [
      pr_review_pipeline(),
      url_change_review(),
      content_safety_webhook(),
      compliance_monitor(),
      a11y_audit(),
      proposal_review()
    ]
  end

  defp pr_review_pipeline do
    %Praxis{
      id: "pr_review_pipeline",
      lobe: :frontal,
      name: "PR Review Pipeline",
      category: :review,
      description:
        "Full PR review via GitHub webhook — quick scan on every PR, full consensus review for flagged ones, with a GitHub PR comment posted back.",
      suggested_team: "Code Review cluster is ideal.",
      requires: [
        {:source_type, "webhook"},
        {:expression_type, "github_pr"}
      ],
      step_definitions: [
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
          expression_name: "github_pr:default"
        }
      ],
      rumination_definition: %{
        name: "PR Review Pipeline Thought",
        description: "Webhook-triggered PR review with GitHub comment for flagged PRs.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "PR Quick Scan", "flow" => "always"},
          %{"step_name" => "PR Full Review", "flow" => "on_flag"},
          %{"step_name" => "Post PR Review Comment", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp url_change_review do
    %Praxis{
      id: "url_change_review",
      lobe: :frontal,
      name: "URL Change Monitor",
      category: :review,
      description:
        "Monitor URLs for content changes and assess their impact. Useful for tracking competitor sites, regulatory pages, or API documentation.",
      suggested_team: "Any cluster with content or risk awareness.",
      requires: [
        {:source_type, "url"},
        {:expression_type, "slack"}
      ],
      step_definitions: [
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
          description: "Full review of a significant URL change — impact and recommended response.",
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
          expression_name: "slack:default"
        }
      ],
      rumination_definition: %{
        name: "URL Change Monitor Thought",
        description: "URL change detection with Slack alert for significant changes.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "URL Change Quick Assessment", "flow" => "always"},
          %{"step_name" => "URL Change Full Review", "flow" => "on_flag"},
          %{"step_name" => "Post URL Change Alert", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp content_safety_webhook do
    %Praxis{
      id: "content_safety_webhook",
      lobe: :frontal,
      name: "Content Safety Review",
      category: :review,
      description:
        "Review user-submitted content via webhook for safety violations. Quick automated scan with full review and Slack escalation for flagged content.",
      suggested_team: "Content Moderation cluster is ideal.",
      requires: [
        {:source_type, "webhook"},
        {:expression_type, "slack"}
      ],
      step_definitions: [
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
          expression_name: "slack:default"
        }
      ],
      rumination_definition: %{
        name: "Content Safety Thought",
        description: "Webhook-triggered content safety review with Slack escalation.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "Content Safety Quick Scan", "flow" => "always"},
          %{"step_name" => "Content Safety Full Review", "flow" => "on_flag"},
          %{"step_name" => "Escalate Content Violation", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp a11y_audit do
    %Praxis{
      id: "a11y_audit",
      lobe: :frontal,
      name: "Accessibility Audit",
      category: :review,
      description:
        "Audit a URL or submitted content for WCAG 2.2 AA compliance. Quick automated scan followed by an evidence-required full audit.",
      suggested_team: "Quality Collective cluster is ideal.",
      requires: [:any_members],
      step_definitions: [
        %{
          name: "A11y Quick Scan",
          description: "Quick automated accessibility scan — does this content need a full audit?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [
            %{
              "who" => "apprentice",
              "preferred_who" => "accessibility-auditor",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: []
        },
        %{
          name: "A11y Full Audit",
          description: "Full consensus accessibility audit — all neurons evaluate against WCAG 2.2 AA.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
          source_ids: []
        },
        %{
          name: "A11y Evidence Check",
          description: "Evidence check — verify findings are backed by specific WCAG criteria and user impact.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{
              "who" => "master",
              "preferred_who" => "evidence-collector",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: []
        }
      ],
      rumination_definition: %{
        name: "Accessibility Audit Thought",
        description: "Source-triggered a11y audit with evidence check for flagged issues.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "A11y Quick Scan", "flow" => "always"},
          %{"step_name" => "A11y Full Audit", "flow" => "on_flag"},
          %{"step_name" => "A11y Evidence Check", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end

  defp proposal_review do
    %Praxis{
      id: "proposal_review",
      lobe: :frontal,
      name: "Proposal Review",
      category: :review,
      description:
        "Put any proposal, design doc, or decision through a gauntlet: Devil's Advocate challenges it, Scope Realist scopes it, Time Traveler evaluates it from the future, Evidence Collector demands proof.",
      suggested_team: "The Skeptics cluster, or any cluster with advisor neurons.",
      requires: [:any_members],
      step_definitions: [
        %{
          name: "Challenge Assumptions",
          description: "Devil's Advocate challenges the core assumptions of the proposal.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{
              "who" => "apprentice",
              "preferred_who" => "devils-advocate",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: []
        },
        %{
          name: "Scope Check",
          description: "Full consensus scope check — is this realistic and well-bounded?",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{
              "who" => "all",
              "preferred_who" => "scope-realist",
              "when" => "on_trigger",
              "how" => "consensus"
            }
          ],
          source_ids: []
        },
        %{
          name: "Future Perspective",
          description: "Time Traveler evaluates the proposal from two years in the future.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{
              "who" => "master",
              "preferred_who" => "time-traveler",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: []
        },
        %{
          name: "Demand Evidence",
          description: "Evidence Collector demands concrete proof for every claim in the proposal.",
          status: "active",
          trigger: "manual",
          schedule: nil,
          roster: [
            %{
              "who" => "master",
              "preferred_who" => "evidence-collector",
              "when" => "on_trigger",
              "how" => "solo"
            }
          ],
          source_ids: []
        }
      ],
      rumination_definition: %{
        name: "Proposal Review Thought",
        description: "Manual proposal gauntlet — challenge, scope, future perspective, evidence.",
        status: "active",
        trigger: "manual",
        schedule: nil,
        steps: [
          %{"step_name" => "Challenge Assumptions", "flow" => "always"},
          %{"step_name" => "Scope Check", "flow" => "always"},
          %{"step_name" => "Future Perspective", "flow" => "always"},
          %{"step_name" => "Demand Evidence", "flow" => "always"}
        ],
        source_ids: []
      }
    }
  end

  defp compliance_monitor do
    %Praxis{
      id: "compliance_monitor",
      lobe: :frontal,
      name: "Compliance Monitor",
      category: :review,
      description:
        "Continuous compliance monitoring from regulatory feeds. Hourly scan for changes to rules, advisories, or standards that affect your operations.",
      suggested_team: "Risk Assessment or Contract Review cluster.",
      requires: [
        {:source_type, "feed"},
        {:expression_type, "slack"}
      ],
      step_definitions: [
        %{
          name: "Compliance Feed Quick Scan",
          description: "Quick scan of incoming regulatory/compliance feed entry — does this affect us?",
          status: "active",
          trigger: "source",
          schedule: nil,
          roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
          source_ids: [],
          context_providers: [
            %{
              "type" => "memory",
              "tags" => ["compliance", "risk"],
              "limit" => 3,
              "sort" => "importance"
            }
          ]
        },
        %{
          name: "Compliance Full Assessment",
          description: "Full assessment of a compliance signal — impact, required response, and timeline.",
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
          expression_name: "slack:default"
        }
      ],
      rumination_definition: %{
        name: "Compliance Monitor Thought",
        description: "Feed-triggered compliance monitoring with Slack alerts.",
        status: "active",
        trigger: "source",
        schedule: nil,
        steps: [
          %{"step_name" => "Compliance Feed Quick Scan", "flow" => "always"},
          %{"step_name" => "Compliance Full Assessment", "flow" => "on_flag"},
          %{"step_name" => "Post Compliance Alert", "flow" => "on_flag"}
        ],
        source_ids: []
      }
    }
  end
end
