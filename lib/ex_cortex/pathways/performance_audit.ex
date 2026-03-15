defmodule ExCortex.Pathways.PerformanceAudit do
  @moduledoc """
  Performance audit pipeline pathway.

  Installs BottleneckDetector + MemoryAnalyst + ResourceEnforcer roles,
  pass/warn/fail/escalate actions, with weighted consensus strategy.
  """

  def metadata do
    %{
      banner: :tech,
      name: "Performance Audit",
      description: "Multi-agent performance analysis and resource optimization pipeline",
      roles: [
        %{
          name: "bottleneck-detector",
          system_prompt: """
          You are a performance bottleneck detector. Identify performance hotspots
          including slow queries, N+1 patterns, blocking operations, excessive
          re-renders, and long task chains. Quantify impact where possible.

          Respond with:
          ACTION: pass | warn | fail | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "thorough", model: "gemma3:4b", strategy: "cod"},
            %{name: "quick", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "memory-analyst",
          system_prompt: """
          You are a memory usage analyst. Evaluate for memory leaks, unbounded growth,
          large allocations, process mailbox buildup, and ETS table bloat. Consider
          both immediate impact and long-running accumulation patterns.

          Respond with:
          ACTION: pass | warn | fail | abstain
          CONFIDENCE: 0.0-1.0
          REASON: your reasoning
          """,
          perspectives: [
            %{name: "conservative", model: "gemma3:4b", strategy: "cod"},
            %{name: "balanced", model: "phi4-mini", strategy: "cot"}
          ]
        },
        %{
          name: "resource-enforcer",
          system_prompt: """
          You are a resource budget enforcer. Evaluate against performance budgets
          for response times, bundle sizes, database connection pools, and CPU
          utilization thresholds. Flag regressions from established baselines.

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
      strategy: {:weighted, weights: %{bottleneck_detector: 1.0, memory_analyst: 1.2, resource_enforcer: 1.0}}
    }
  end

  def quest_definitions do
    [
      %{
        name: "Performance Quick Scan",
        description: "Quick automated performance analysis by apprentice neurons",
        status: "active",
        trigger: "scheduled",
        schedule: "@hourly",
        roster: [%{"who" => "apprentice", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        context_providers: [%{"type" => "memory", "tags" => ["performance"], "limit" => 3, "sort" => "importance"}],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Full Performance Audit",
        description: "Comprehensive performance analysis by all neurons reaching consensus",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "all", "when" => "on_trigger", "how" => "consensus"}],
        source_ids: [],
        escalate: true,
        escalate_threshold: 0.6
      },
      %{
        name: "Performance Baseline Memory",
        description: """
        Synthesize performance findings into a current baseline entry. Document:
        key metrics for hot paths, known bottlenecks with context (severity, when found,
        whether being addressed), optimization wins already applied (so they are not
        re-recommended), and regressions detected with probable causes. Always replace
        the previous entry — this represents current system performance reality.
        """,
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "artifact",
        write_mode: "replace",
        entry_title_template: "Performance Baselines — Current",
        log_title_template: nil,
        context_providers: [%{"type" => "memory", "tags" => ["performance"], "limit" => 5, "sort" => "importance"}],
        loop_mode: "reflect",
        loop_tools: ["query_lore", "search_github"]
      },
      %{
        name: "File Performance Regression",
        description: "Open a GitHub issue tracking a confirmed performance regression",
        status: "active",
        trigger: "manual",
        schedule: nil,
        roster: [%{"who" => "master", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "github_issue",
        herald_name: "github_issue:default"
      },
      %{
        name: "Post Performance Alert",
        description: "Post a performance regression alert to the team Slack channel",
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
        name: "Performance Audit Campaign",
        description: "Automated scan that escalates to full audit on any performance regressions",
        status: "active",
        trigger: "scheduled",
        schedule: "@daily",
        steps: [
          %{"thought_name" => "Performance Quick Scan", "flow" => "always"},
          %{"thought_name" => "Full Performance Audit", "flow" => "on_flag"},
          %{"thought_name" => "File Performance Regression", "flow" => "on_flag"},
          %{"thought_name" => "Post Performance Alert", "flow" => "on_flag"},
          %{"thought_name" => "Performance Baseline Memory", "flow" => "always"}
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
