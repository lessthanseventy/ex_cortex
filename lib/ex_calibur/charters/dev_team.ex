defmodule ExCalibur.Charters.DevTeam do
  @moduledoc """
  Dev Team charter — the self-improvement guild.

  Installs Project Manager, Product Analyst, Code Writer, Code Reviewer,
  QA / Test Writer, and UX Designer. Gives ExCalibur a team of AI members
  to work on itself via the self-improvement loop.
  """

  def metadata do
    %{
      banner: :tech,
      name: "Dev Team",
      description:
        "Self-improvement guild — AI members that triage issues, write code, review PRs, run tests, and ship improvements to ExCalibur itself.",
      roles: [
        %{
          name: "Project Manager",
          system_prompt: """
          You are the Project Manager of the ExCalibur Dev Team. Your job is to triage GitHub issues labeled 'self-improvement', prioritize them, and coordinate the team. For each issue: evaluate if it should be worked (reject trivial, duplicate, or out-of-scope issues), write an implementation plan, and after implementation is complete, decide whether to auto-merge (low-risk changes: formatting, docs, tests, small fixes) or escalate to the CTO via a lodge proposal (core logic, new features, dependency changes). Be decisive and opinionated about scope.
          """,
          perspectives: [
            %{name: "quick", model: "gemma3:4b", strategy: "cot"},
            %{name: "thorough", model: "gemma3:12b", strategy: "cod"}
          ]
        },
        %{
          name: "Product Analyst",
          system_prompt: """
          You are the Product Analyst of the ExCalibur Dev Team. You understand how the user actually uses ExCalibur. Read their Obsidian notes to understand their workflows and frustrations. Query Lore for evaluation patterns. Check git history to find high-churn files (pain points). File GitHub issues for problems you discover, prioritized by user impact — not just code quality. Focus on: what frustrates the user, what they do repeatedly, what is missing from their workflow. File at most 3 issues per run.
          """,
          perspectives: [
            %{name: "quick", model: "gemma3:4b", strategy: "cot"},
            %{name: "thorough", model: "gemma3:12b", strategy: "cod"}
          ]
        },
        %{
          name: "Code Writer",
          system_prompt: """
          You are the Code Writer of the ExCalibur Dev Team. You implement GitHub issues assigned to you. Your working directory is a git worktree isolated from the live app. Steps: (1) read the relevant files to understand the codebase, (2) write the implementation following existing patterns, (3) run tests via run_sandbox to verify, (4) commit and push, (5) open a PR. Write idiomatic Elixir. Follow existing module patterns. Test-first when practical.
          """,
          perspectives: [
            %{name: "quick", model: "gemma3:4b", strategy: "cot"},
            %{name: "thorough", model: "gemma3:12b", strategy: "cod"}
          ]
        },
        %{
          name: "Code Reviewer",
          system_prompt: """
          You are the Code Reviewer of the ExCalibur Dev Team. Review pull requests for correctness, security, and adherence to existing patterns. Check: does it follow the Elixir/Phoenix conventions in this codebase? Are there edge cases? Security issues? Does it match the issue requirements? Comment on the PR with your findings. If changes are needed, say so clearly. If it looks good, approve. Also note any unrelated issues you spot for future issues (but don't block on them).
          """,
          perspectives: [
            %{name: "quick", model: "gemma3:4b", strategy: "cot"},
            %{name: "thorough", model: "gemma3:12b", strategy: "cod"}
          ]
        },
        %{
          name: "QA / Test Writer",
          system_prompt: """
          You are the QA and Test Writer for the ExCalibur Dev Team. Your job is to verify that changes are tested and working. Run the test suite via run_sandbox. Run mix credo. Check that new code has tests. If tests are missing or insufficient, write them. If tests fail, report what failed and why. Your verdict gates whether the PR can merge.
          """,
          perspectives: [
            %{name: "quick", model: "gemma3:4b", strategy: "cot"},
            %{name: "thorough", model: "gemma3:12b", strategy: "cod"}
          ]
        },
        %{
          name: "UX Designer",
          system_prompt: """
          You are the UX Designer for the ExCalibur Dev Team. You review changes to LiveView templates and UI components for accessibility and usability. Run mix excessibility to check for accessibility violations — use this as context, not as a hard gate. Give your opinion on whether UI changes improve or worsen the user experience. Note any pre-existing issues you spot (they may become future issues) but focus your verdict on the current change.
          """,
          perspectives: [
            %{name: "quick", model: "gemma3:4b", strategy: "cot"},
            %{name: "thorough", model: "gemma3:12b", strategy: "cod"}
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
            "tools" => "write"
          }
        }
      end)
    end)
  end

  def quest_definitions do
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
        output_type: "lodge_card",
        pin_slug: "dev-triage",
        pinned: true,
        loop_mode: "reflect",
        loop_tools: ["search_github", "comment_github", "close_issue", "query_lore"]
      },
      %{
        name: "Analyze Usage",
        description:
          "Product Analyst reads Obsidian notes and queries Lore to understand user workflows and frustrations, then files up to 3 GitHub issues.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 10 * * 1",
        roster: [%{"who" => "journeyman", "preferred_who" => "Product Analyst", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "lodge_card",
        loop_mode: "reflect",
        loop_tools: ["read_obsidian", "query_lore", "search_github", "create_github_issue", "read_file", "list_files", "run_sandbox"]
      },
      %{
        name: "Implement Issue",
        description:
          "Code Writer picks up an assigned issue and implements it in a worktree — reads code, writes implementation, runs tests, opens a PR.",
        status: "active",
        trigger: "manual",
        roster: [%{"who" => "journeyman", "preferred_who" => "Code Writer", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "lodge_card",
        loop_mode: "reflect",
        loop_tools: ["read_file", "list_files", "write_file", "edit_file", "git_commit", "git_push", "open_pr", "run_sandbox"]
      },
      %{
        name: "Review PR",
        description:
          "Code Reviewer examines an open PR for correctness, security, and pattern adherence — comments findings and approves or requests changes.",
        status: "active",
        trigger: "manual",
        roster: [%{"who" => "journeyman", "preferred_who" => "Code Reviewer", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "lodge_card",
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
        output_type: "lodge_card",
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
        output_type: "lodge_card",
        loop_mode: "reflect",
        loop_tools: ["read_file", "list_files", "run_sandbox", "comment_github"]
      },
      %{
        name: "Merge Decision",
        description:
          "Project Manager reviews QA and review outcomes and decides: auto-merge (low-risk) or escalate to CTO via lodge proposal.",
        status: "active",
        trigger: "manual",
        roster: [%{"who" => "journeyman", "preferred_who" => "Project Manager", "when" => "on_trigger", "how" => "solo"}],
        source_ids: [],
        output_type: "lodge_card",
        loop_mode: "reflect",
        loop_tools: ["search_github", "merge_pr", "comment_github", "git_pull", "restart_app"]
      }
    ]
  end

  def campaign_definitions do
    [
      %{
        name: "Daily Dev Triage",
        description: "Morning triage of self-improvement issues, followed by usage analysis on Mondays.",
        status: "active",
        trigger: "scheduled",
        schedule: "0 9 * * *",
        steps: [
          %{"quest_name" => "Triage Issues", "flow" => "always"}
        ],
        source_ids: []
      },
      %{
        name: "Self-Improvement Loop",
        description: "Full loop: implement an issue, review, QA, UX check, then decide to merge or escalate.",
        status: "active",
        trigger: "manual",
        steps: [
          %{"quest_name" => "Implement Issue", "flow" => "always"},
          %{"quest_name" => "Review PR", "flow" => "always"},
          %{"quest_name" => "QA Check", "flow" => "always"},
          %{"quest_name" => "UX Review", "flow" => "on_flag"},
          %{"quest_name" => "Merge Decision", "flow" => "always"}
        ],
        source_ids: []
      }
    ]
  end
end
