defmodule ExCalibur.Charters.ContentModeration do
  @moduledoc """
  Content moderation pipeline charter.

  Installs SafetyReviewer + BiasChecker + PolicyEnforcer roles,
  flag/approve/reject/escalate actions, with majority consensus strategy.
  """

  def metadata do
    %{
      banner: :lifestyle,
      name: "Content Moderation",
      description: "Multi-agent content safety review pipeline",
      roles: [
        %{
          name: "safety-reviewer",
          system_prompt: """
          You are a content safety reviewer. Evaluate content for harmful, dangerous,
          or inappropriate material. Consider violence, hate speech, self-harm,
          illegal activities, and age-inappropriate content.

          Respond with:
          ACTION: approve | reject | flag | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "strict", model: "gemma3:4b", strategy: "cod"},
            %{name: "moderate", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "bias-checker",
          system_prompt: """
          You are a bias and fairness checker. Evaluate content for discriminatory
          language, stereotypes, cultural insensitivity, and unequal treatment
          of protected groups.

          Respond with:
          ACTION: approve | reject | flag | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "alpha", model: "gemma3:4b", strategy: "cod"},
            %{name: "beta", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "policy-enforcer",
          system_prompt: """
          You are a platform policy enforcer. Evaluate content against community
          guidelines and terms of service. Check for spam, misinformation,
          impersonation, and platform-specific rule violations.

          Respond with:
          ACTION: approve | reject | flag | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "alpha", model: "gemma3:4b", strategy: "cod"},
            %{name: "beta", model: "phi4-mini", strategy: "cot"}
          ]
        }
      ],
      actions: [:approve, :reject, :flag, :escalate],
      strategy: :majority
    }
  end

  def quest_definitions do
    [
      %{
        name: "Content Safety Scan",
        description: "Quick automated content safety check by apprentice members",
        status: "active",
        trigger: "scheduled",
        schedule: "@hourly",
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        context_providers: [
          %{
            "type" => "static",
            "text" =>
              "Community standards: maintain respectful discourse. Hate speech, harassment, and graphic violence are not permitted. Gray areas should be escalated."
          },
          %{"type" => "lore", "tags" => ["moderation"], "limit" => 3, "sort" => "newest"}
        ],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Full Content Review",
        description: "Comprehensive moderation review by all members reaching consensus",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Moderation Edge Case Log",
        description: """
        Synthesize moderation decisions on edge cases into institutional memory. Document:
        gray-area content types and how they were ruled, evolving community standards applied,
        escalation decisions and their outcomes, and any inconsistencies noted across reviewers.
        This helps the guild stay consistent over time.
        """,
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "both",
        entry_title_template: "Moderation Patterns",
        log_title_template: "Moderation Log — {date}",
        context_providers: [%{"type" => "lore", "tags" => ["moderation"], "limit" => 5, "sort" => "newest"}],
        loop_mode: "reflect",
        loop_tools: ["query_lore"]
      },
      %{
        name: "Escalate Moderation Alert",
        description: "Post a moderation escalation alert to the team Slack channel",
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
        name: "Continuous Moderation Campaign",
        description: "Automated scan that escalates to full review on any flagged content",
        status: "active",
        trigger: "scheduled",
        schedule: "@hourly",
        steps: [
          %{"quest_name" => "Content Safety Scan", "flow" => "always"},
          %{"quest_name" => "Full Content Review", "flow" => "on_flag"},
          %{"quest_name" => "Escalate Moderation Alert", "flow" => "on_flag"},
          %{"quest_name" => "Moderation Edge Case Log", "flow" => "always"}
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
