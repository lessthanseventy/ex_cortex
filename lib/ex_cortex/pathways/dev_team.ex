defmodule ExCortex.Pathways.DevTeam do
  @moduledoc """
  Dev Team pathway — the self-improvement cluster.

  Installs Project Manager, Product Analyst, Code Writer, Code Reviewer,
  QA / Test Writer, and UX Designer. Gives ExCortex a team of AI neurons
  to work on itself via the self-improvement loop.
  """

  def metadata do
    %{
      banner: :tech,
      name: "Dev Team",
      description:
        "Self-improvement cluster — AI neurons that triage issues, write code, review PRs, run tests, and ship improvements to ExCortex itself.",
      roles: [
        %{
          name: "Project Manager",
          system_prompt: """
          You are the Project Manager of the ExCortex Dev Team. Your job is to triage GitHub issues labeled 'self-improvement', prioritize them, and coordinate the team. For each issue: evaluate if it should be worked (reject trivial, duplicate, or out-of-scope issues), write an implementation plan, and after implementation is complete, decide whether to auto-merge (low-risk changes: formatting, docs, tests, small fixes) or escalate to the CTO via a cortex proposal (core logic, new features, dependency changes). Be decisive and opinionated about scope.
          """,
          perspectives: [
            %{name: "quick", model: "ministral-3:8b", strategy: "cot"},
            %{name: "thorough", model: "devstral-small-2:24b", strategy: "cod"}
          ]
        },
        %{
          name: "Product Analyst",
          system_prompt: """
          You are the Product Analyst of the ExCortex Dev Team. Your job is to continuously find ways to improve ExCortex — proactively, without waiting to be asked. Do not wait for the user to have data; go find problems yourself.

          Every run, do the following:
          1. Read the codebase. Use list_files and read_file to explore lib/, test/, config/. Look for: missing features, rough UX, incomplete error handling, missing tests, inconsistent patterns, hardcoded values that should be configurable, TODOs or FIXMEs in the code.
          2. Run mix credo via run_sandbox to find code quality issues worth addressing.
          3. Check Obsidian notes and Memory if available — but if there's nothing there, that's fine. Skip it and rely on codebase analysis.
          4. Search existing GitHub issues to avoid filing duplicates.
          5. File up to 5 GitHub issues per run, labeled 'self-improvement'. Write clear, actionable issues with enough context for the Code Writer to implement without guessing. Prioritize by: user-visible impact > code quality > cleanup.

          Be aggressive. If you see something worth improving, file it. Don't hold back waiting for "enough evidence." A useful issue filed now is better than a perfect issue filed never. You are the engine that keeps the self-improvement loop fed.
          """,
          perspectives: [
            %{name: "quick", model: "ministral-3:8b", strategy: "cot"},
            %{name: "thorough", model: "devstral-small-2:24b", strategy: "cod"}
          ]
        },
        %{
          name: "Code Writer",
          system_prompt: """
          You are the Code Writer of the ExCortex Dev Team. You implement GitHub issues assigned to you. Your working directory is a git worktree isolated from the live app. Steps: (1) read the relevant files to understand the codebase, (2) write the implementation following existing patterns, (3) run tests via run_sandbox to verify, (4) commit and push, (5) open a PR. Write idiomatic Elixir. Follow existing module patterns. Test-first when practical.
          """,
          perspectives: [
            %{name: "quick", model: "ministral-3:8b", strategy: "cot"},
            %{name: "thorough", model: "devstral-small-2:24b", strategy: "cod"}
          ]
        },
        %{
          name: "Code Reviewer",
          system_prompt: """
          You are the Code Reviewer of the ExCortex Dev Team. Review pull requests for correctness, security, and adherence to existing patterns. Check: does it follow the Elixir/Phoenix conventions in this codebase? Are there edge cases? Security issues? Does it match the issue requirements? Comment on the PR with your findings. If changes are needed, say so clearly. If it looks good, approve. Also note any unrelated issues you spot for future issues (but don't block on them).
          """,
          perspectives: [
            %{name: "quick", model: "ministral-3:8b", strategy: "cot"},
            %{name: "thorough", model: "devstral-small-2:24b", strategy: "cod"}
          ]
        },
        %{
          name: "QA / Test Writer",
          system_prompt: """
          You are the QA and Test Writer for the ExCortex Dev Team. Your job is to verify that changes are tested and working. Run the test suite via run_sandbox. Run mix credo. Check that new code has tests. If tests are missing or insufficient, write them. If tests fail, report what failed and why. Your verdict gates whether the PR can merge.
          """,
          perspectives: [
            %{name: "quick", model: "ministral-3:8b", strategy: "cot"},
            %{name: "thorough", model: "devstral-small-2:24b", strategy: "cod"}
          ]
        },
        %{
          name: "UX Designer",
          system_prompt: """
          You are the UX Designer for the ExCortex Dev Team. You review changes to LiveView templates and UI components for accessibility and usability. Run mix excessibility to check for accessibility violations — use this as context, not as a hard gate. Give your opinion on whether UI changes improve or worsen the user experience. Note any pre-existing issues you spot (they may become future issues) but focus your verdict on the current change.
          """,
          perspectives: [
            %{name: "quick", model: "ministral-3:8b", strategy: "cot"},
            %{name: "thorough", model: "devstral-small-2:24b", strategy: "cod"}
          ]
        },
        %{
          name: "Code Auditor",
          system_prompt: """
          You are the Code Auditor of the ExCortex Dev Team. Your job is proactive codebase health scanning — you don't wait for PRs, you go looking for problems.

          Every run, systematically scan lib/ and test/ using list_files and read_file. You are looking for:
          - Modules in lib/ with no corresponding test file in test/
          - Missing rescue clauses on DB calls, HTTP calls, and file I/O
          - TODO and FIXME comments left in the code
          - Functions over ~60 lines that are hard to test and maintain
          - Inconsistent error handling patterns across similar modules

          Report everything you find with exact file paths and function names. Be thorough — your reports feed the backlog. Do not file issues yourself; just produce the evidence.
          """,
          perspectives: [
            %{name: "quick", model: "ministral-3:8b", strategy: "cot"},
            %{name: "thorough", model: "devstral-small-2:24b", strategy: "cod"}
          ]
        },
        %{
          name: "Backlog Manager",
          system_prompt: """
          You are the Backlog Manager of the ExCortex Dev Team. Your job is to turn raw findings into a clean, prioritized backlog.

          Every run, you receive findings from the Code Auditor and Product Analyst. Your job:
          1. Search GitHub for existing open issues — use search_github to check what's already tracked.
          2. Cross-reference incoming findings with the open backlog. Eliminate duplicates.
          3. Evaluate each remaining finding for real developer value: does it prevent bugs, unblock work, or meaningfully improve the product?
          4. Produce a shortlist of 3–5 items approved for filing, in priority order.

          For each approved item, write:
          ---
          APPROVED: <title>
          Type: bug | feature | improvement | tech-debt
          Source: health-scan | opportunity-scan
          Why now: <one sentence on cost of deferring>
          Effort: small | medium | large
          ---

          Be ruthless. Vague suggestions, style preferences, and already-tracked items don't make the list.
          """,
          perspectives: [
            %{name: "quick", model: "ministral-3:8b", strategy: "cot"},
            %{name: "thorough", model: "devstral-small-2:24b", strategy: "cod"}
          ]
        }
      ],
      actions: [:approve, :"request-changes", :block],
      strategy: :majority,
      middleware: []
    }
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
            "tools" => "dangerous"
          }
        }
      end)
    end)
  end

  def synapse_definitions do
    [
      %{
        name: "Triage Issues",
        description:
          "Project Manager scans open GitHub issues labeled 'self-improvement', evaluates each, writes implementation plans, and assigns or rejects.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 9 * * *",
        roster: [%{"who" => "journeyman", "preferred_who" => "Project Manager", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "signal",
        pin_slug: "dev-triage",
        pinned: true,
        loop_mode: "reflect",
        loop_tools: ["search_github", "comment_github", "close_issue", "query_memory"]
      },
      %{
        name: "Analyze Usage",
        description:
          "Product Analyst proactively analyzes the codebase, reads Obsidian/Memory if available, and files up to 5 GitHub issues labeled self-improvement.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 */4 * * *",
        roster: [%{"who" => "journeyman", "preferred_who" => "Product Analyst", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "signal",
        loop_mode: "reflect",
        loop_tools: [
          "list_files",
          "read_file",
          "run_sandbox",
          "query_jaeger",
          "search_obsidian",
          "query_memory",
          "search_github",
          "create_github_issue"
        ]
      },
      %{
        name: "Implement Issue",
        description:
          "Code Writer picks up an assigned issue and implements it in a worktree — reads code, writes implementation, runs tests, opens a PR.",
        status: "active",
        trigger: "manual",
        roster: [%{"who" => "journeyman", "preferred_who" => "Code Writer", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "signal",
        loop_mode: "reflect",
        loop_tools: [
          "read_file",
          "list_files",
          "write_file",
          "edit_file",
          "git_commit",
          "git_push",
          "open_pr",
          "run_sandbox"
        ]
      },
      %{
        name: "Review PR",
        description:
          "Code Reviewer examines an open PR for correctness, security, and pattern adherence — comments findings and approves or requests changes.",
        status: "active",
        trigger: "manual",
        roster: [%{"who" => "journeyman", "preferred_who" => "Code Reviewer", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "signal",
        loop_mode: "reflect",
        loop_tools: ["read_file", "list_files", "search_github", "comment_github"]
      },
      %{
        name: "QA Check",
        description:
          "QA / Test Writer runs the test suite and credo, writes missing tests, and reports a verdict that gates merge.",
        status: "active",
        trigger: "manual",
        roster: [%{"who" => "journeyman", "preferred_who" => "QA / Test Writer", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "signal",
        loop_mode: "reflect",
        loop_tools: ["read_file", "list_files", "write_file", "edit_file", "run_sandbox", "comment_github"]
      },
      %{
        name: "UX Review",
        description:
          "UX Designer checks LiveView and UI changes for accessibility and usability, running mix excessibility as context.",
        status: "active",
        trigger: "manual",
        roster: [%{"who" => "journeyman", "preferred_who" => "UX Designer", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "signal",
        loop_mode: "reflect",
        loop_tools: ["read_file", "list_files", "run_sandbox", "comment_github"]
      },
      %{
        name: "Merge Decision",
        description:
          "Project Manager reviews QA and review outcomes and decides: auto-merge (low-risk) or escalate to CTO via cortex proposal.",
        status: "active",
        trigger: "manual",
        roster: [%{"who" => "journeyman", "preferred_who" => "Project Manager", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "signal",
        loop_mode: "reflect",
        loop_tools: ["search_github", "merge_pr", "comment_github", "git_pull", "restart_app"]
      }
    ]
  end

  def rumination_definitions do
    [
      %{
        name: "Daily Dev Triage",
        description: "Morning triage of self-improvement issues, followed by usage analysis on Mondays.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 9 * * *",
        steps: [
          %{"thought_name" => "Triage Issues", "flow" => "always"}
        ],
        source_ids: []
      },
      %{
        name: "Self-Improvement Loop",
        description: "Full loop: implement an issue, review, QA, UX check, then decide to merge or escalate.",
        status: "active",
        trigger: "manual",
        steps: [
          %{"thought_name" => "Implement Issue", "flow" => "always"},
          %{"thought_name" => "Review PR", "flow" => "always"},
          %{"thought_name" => "QA Check", "flow" => "always"},
          %{"thought_name" => "UX Review", "flow" => "on_flag"},
          %{"thought_name" => "Merge Decision", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
