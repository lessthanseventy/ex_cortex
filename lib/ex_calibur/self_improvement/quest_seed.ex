defmodule ExCalibur.SelfImprovement.QuestSeed do
  @moduledoc "Seeds the self-improvement pipeline — called when Dev Team charter is installed."

  import Ecto.Query

  alias ExCalibur.Lore.LoreEntry
  alias ExCalibur.Quests
  alias ExCalibur.Quests.Quest
  alias ExCalibur.Quests.Step
  alias ExCalibur.Repo
  alias ExCalibur.Sources.Source

  @si_step_names [
    "SI: PM Triage",
    "SI: Code Writer",
    "SI: Code Reviewer",
    "SI: QA",
    "SI: UX Designer",
    "SI: PM Merge Decision",
    "SI: Static Analysis",
    "SI: Product Analyst Sweep"
  ]

  @si_quest_names ["Self-Improvement Loop", "SI: Analyst Sweep"]

  def seed(opts \\ %{}) do
    repo = Map.get(opts, :repo, "")
    cleanup()

    with {:ok, source} <- create_source(repo),
         {:ok, steps} <- create_steps(),
         {:ok, quest} <- create_quest(source, steps),
         {:ok, analysis_step} <- create_static_analysis_step(),
         {:ok, sweep_step} <- create_sweep_step(),
         {:ok, sweep_quest} <- create_sweep_quest(analysis_step, sweep_step) do
      seed_lore()
      {:ok, %{source: source, steps: steps, quest: quest, sweep_quest: sweep_quest}}
    end
  end

  defp cleanup do
    Repo.delete_all(from q in Quest, where: q.name in @si_quest_names)
    Repo.delete_all(from s in Step, where: s.name in @si_step_names)

    Repo.delete_all(
      from s in Source,
        where: s.source_type == "github_issues" and s.name == "Self-Improvement Issues"
    )
  end

  # --- Private ---

  defp create_source(repo) do
    %Source{}
    |> Source.changeset(%{
      name: "Self-Improvement Issues",
      source_type: "github_issues",
      config: %{
        "repo" => repo,
        "label" => "self-improvement",
        "interval" => 3_600_000
      },
      status: "active"
    })
    |> Repo.insert()
  end

  defp create_steps do
    step_attrs = [
      %{
        name: "SI: PM Triage",
        description: """
        You are the Project Manager for the ExCalibur self-improvement pipeline.

        You will receive a single GitHub issue. Your job:
        1. Read the issue carefully.
        2. Search GitHub to confirm it is not a duplicate of an existing open issue.
        3. Check whether it describes a real, actionable problem (not a vague refactoring suggestion or credo baseline noise).
        4. If proceeding: write a concrete implementation plan (what files to touch, what to change, how to test it).

        End your response with EXACTLY one of these lines:
          DECISION: PROCEED #<issue_number> "<issue_title>"
          DECISION: REJECT "<reason>"

        Do not summarize multiple issues. Focus only on the issue provided as input.
        """,
        trigger: "manual",
        output_type: "freeform",
        dangerous_tool_mode: "execute",
        max_tool_iterations: 10,
        roster: [
          %{
            "who" => "all",
            "preferred_who" => "Project Manager",
            "how" => "solo",
            "when" => "sequential"
          }
        ]
      },
      %{
        name: "SI: Code Writer",
        description: """
        You are the Code Writer for the ExCalibur self-improvement pipeline.

        The previous step (PM Triage) has selected a specific GitHub issue and written an implementation plan.
        Find the DECISION line in your context to identify which issue to work on.

        Follow this workflow exactly:
        1. Call setup_worktree to create an isolated git branch for this work.
        2. Use list_files and read_file to understand the relevant code before touching anything.
        3. Implement the change described in the PM's plan — minimal, focused, no scope creep.
        4. Run `mix test` via run_sandbox. Fix any failures before proceeding.
        5. Run `mix credo --all` via run_sandbox. Fix any new warnings you introduced.
        6. Commit with git_commit (message: "fix: <short description> (closes #N)").
        7. Push with git_push.
        8. Open a PR with open_pr. Title: fix title. Body: reference the issue number.
        9. End your response with: PR: <url>

        If PM Triage decided REJECT, output: SKIPPED: PM rejected this issue.
        Do not open a PR for a rejected issue.
        """,
        trigger: "manual",
        output_type: "freeform",
        dangerous_tool_mode: "execute",
        max_tool_iterations: 15,
        loop_mode: "reflect",
        max_iterations: 5,
        loop_tools: [
          "setup_worktree",
          "read_file",
          "list_files",
          "write_file",
          "edit_file",
          "git_commit",
          "git_push",
          "open_pr",
          "run_sandbox"
        ],
        roster: [
          %{
            "who" => "journeyman",
            "preferred_who" => "Code Writer",
            "how" => "solo",
            "when" => "sequential"
          }
        ]
      },
      %{
        name: "SI: Code Reviewer",
        description: """
        You are the Code Reviewer for the ExCalibur self-improvement pipeline.

        Find the PR URL in your context (look for "PR: <url>"). If the Code Writer output
        "SKIPPED", output verdict=abstain with reason "No PR to review — issue was rejected or skipped."

        If there is a PR to review:
        1. Use read_file and list_files to examine the changed files.
        2. Check for: correctness, test coverage, pattern adherence, no scope creep, no new credo warnings.
        3. Issue your verdict: pass (looks good), warn (minor issues), fail (must not merge).
        """,
        trigger: "manual",
        output_type: "verdict",
        dangerous_tool_mode: "intercept",
        max_tool_iterations: 10,
        loop_tools: ["read_file", "list_files", "run_sandbox"],
        roster: [
          %{
            "who" => "all",
            "preferred_who" => "Code Reviewer",
            "how" => "solo",
            "when" => "sequential"
          }
        ]
      },
      %{
        name: "SI: QA",
        description: """
        You are the QA reviewer for the ExCalibur self-improvement pipeline.

        If the Code Writer output "SKIPPED", output verdict=abstain with reason "No code to test."

        Your job is to VERIFY, not to write code. Do not create or modify any files.

        1. Run `mix test` via run_sandbox. Report pass/fail.
        2. Run `mix credo --all` via run_sandbox. Report any NEW warnings (ignore the ~46 pre-existing baseline issues listed in your lore).
        3. Issue your verdict: pass (all tests pass, no new credo warnings), warn (tests pass but minor concerns), fail (test failures or new credo errors).
        """,
        trigger: "manual",
        output_type: "verdict",
        dangerous_tool_mode: "intercept",
        max_tool_iterations: 10,
        loop_mode: "reflect",
        max_iterations: 3,
        loop_tools: ["run_sandbox", "read_file"],
        context_providers: [
          %{"type" => "lore", "tags" => ["credo", "baseline"], "sort" => "importance", "limit" => 1}
        ],
        roster: [
          %{
            "who" => "all",
            "preferred_who" => "QA / Test Writer",
            "how" => "solo",
            "when" => "sequential"
          }
        ]
      },
      %{
        name: "SI: UX Designer",
        description: """
        UX Designer reviews LiveView and UI changes for accessibility and usability.

        Run `mix excessibility` via run_sandbox to get the current accessibility report.
        That is the correct command — do not use `mix test`, `mix test check`, or any other variant.
        Review the output and assess whether the changes introduced or resolved accessibility issues.
        """,
        trigger: "manual",
        output_type: "verdict",
        dangerous_tool_mode: "execute",
        max_tool_iterations: 10,
        loop_tools: ["run_sandbox"],
        roster: [
          %{
            "who" => "all",
            "preferred_who" => "UX Designer",
            "how" => "solo",
            "when" => "sequential"
          }
        ]
      },
      %{
        name: "SI: PM Merge Decision",
        description:
          "Project Manager reviews QA and review outcomes and decides: auto-merge low-risk changes or escalate to CTO via lodge proposal.",
        trigger: "manual",
        output_type: "freeform",
        dangerous_tool_mode: "execute",
        max_tool_iterations: 10,
        roster: [
          %{
            "who" => "all",
            "preferred_who" => "Project Manager",
            "how" => "solo",
            "when" => "sequential"
          }
        ]
      }
    ]

    results = Enum.map(step_attrs, &Quests.create_step/1)

    case Enum.find(results, fn r -> match?({:error, _}, r) end) do
      nil -> {:ok, Enum.map(results, fn {:ok, step} -> step end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_quest(source, steps) do
    # Gate flags: Code Reviewer (index 2) and QA (index 3) are verdict gates
    gate_indices = MapSet.new([2, 3])

    step_entries =
      steps
      |> Enum.with_index(1)
      |> Enum.map(fn {step, order} ->
        entry = %{"step_id" => step.id, "order" => order}
        if order in gate_indices, do: Map.put(entry, "gate", true), else: entry
      end)

    Quests.create_quest(%{
      name: "Self-Improvement Loop",
      description:
        "Full self-improvement pipeline: PM triage, code writing, code review, QA, UX check, then merge decision.",
      trigger: "source",
      source_ids: [to_string(source.id)],
      steps: step_entries,
      status: "active"
    })
  end

  defp create_static_analysis_step do
    Quests.create_step(%{
      name: "SI: Static Analysis",
      description: """
      Run static analysis tools and output the raw results. Do not interpret or filter them.

      1. Run `mix credo --all` via run_sandbox.
      2. Run `mix deps.audit` via run_sandbox.

      Format your output exactly like this:

      ## Credo Findings
      <full credo output>

      ## Dependency Audit
      <full deps.audit output>

      That is all. Do not file issues, do not draw conclusions, do not make recommendations.
      The next step will analyze these findings.
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "intercept",
      max_tool_iterations: 5,
      roster: [
        %{
          "who" => "apprentice",
          "how" => "solo",
          "when" => "sequential"
        }
      ]
    })
  end

  defp create_sweep_step do
    Quests.create_step(%{
      name: "SI: Product Analyst Sweep",
      description: """
      Product Analyst analyzes the static analysis findings from the previous step and
      files up to 3 high-value GitHub issues labeled self-improvement.

      Your context includes the full credo and deps.audit output from the Static Analysis step.

      IMPORTANT — before filing any issue:
      1. Cross-reference against the credo baseline in your lore. Do NOT file issues for anything on that list.
      2. Search GitHub to confirm the issue does not already exist as an open issue.
      3. Only file issues for NEW problems not in the baseline, or architectural issues worth addressing.

      You may also browse the codebase (read_file, list_files) to understand context around any finding.
      File at most 3 issues total. Quality over quantity — a real bug or clear pattern problem is worth more
      than three vague suggestions.
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "intercept",
      max_tool_iterations: 10,
      loop_mode: "reflect",
      max_iterations: 3,
      loop_tools: ["read_file", "list_files", "query_lore"],
      context_providers: [
        %{"type" => "lore", "tags" => ["credo", "baseline"], "sort" => "importance", "limit" => 1}
      ],
      roster: [
        %{
          "who" => "journeyman",
          "how" => "solo",
          "when" => "sequential"
        }
      ]
    })
  end

  @lore_entries [
    %{
      title: "José Valim's Grimoire: Elixir Testing Patterns",
      tags: ["elixir", "testing", "patterns", "grimoire"],
      importance: 5,
      body: """
      # José Valim's Grimoire: Elixir Testing Patterns

      *Authoritative guidance on modern Elixir testing for this codebase.*

      ## Never mock module functions by assignment

      This is invalid Elixir — modules are compiled bytecode, not mutable objects:

      ```elixir
      # WRONG — will not compile
      MyModule.some_function = fn _ -> :ok end
      ```

      For DB-dependent code, use real data. For external services, inject the dependency
      or define a behaviour and use `Mox`. When in doubt, test with the real thing.

      ## Use DataCase for anything that touches the database

      ```elixir
      defmodule MyTest do
        use ExUnit.Case, async: true   # pure unit test, no DB
      end

      defmodule MyRepoTest do
        use ExCalibur.DataCase, async: true  # wraps in rolled-back transaction
      end
      ```

      `async: true` is safe on DataCase. Use `async: false` only when tests share global
      state (PubSub subscriptions, named processes).

      ## Non-empty list checks

      ```elixir
      assert length(list) > 0  # SLOW — O(n) traversal
      assert list != []         # FAST — prefer this
      assert [_ | _] = list    # Best when you need the first element too
      ```

      ## Assert on structure, not just truthiness

      ```elixir
      assert result                        # Weak
      assert {:ok, %{id: id}} = result    # Better — asserts shape and binds value
      ```

      ## Async messages: assert_receive, not sleep

      ```elixir
      Process.sleep(100)                       # BAD
      assert_receive {:event, :x}, 500         # GOOD
      ```

      ## Test the public interface, not private functions

      Private functions are implementation details. Test them indirectly through the public API.
      If a private function is complex enough to test directly, it should be its own module.
      """
    },
    %{
      title: "ExCalibur: Working Tree Noise",
      tags: ["project", "worktree", "git", "snapshots", "noise"],
      importance: 4,
      body: """
      # ExCalibur: Working Tree Noise

      Certain files will *always* appear modified in `git diff`. Do not treat them as problems.

      ## `test/excessibility/html_snapshots/`

      Auto-generated by the accessibility test suite (`mix excessibility`). Every time the
      test suite runs, Phoenix LiveView renders fresh HTML and rewrites these files.
      They will always show as modified and will always fail `mix format --check-formatted`.
      **This is expected and normal.**

      - Do NOT file issues about unformatted snapshot files
      - Do NOT try to fix them with `mix format`
      - If `mix format --check-formatted` fails and the only changed files are in this
        directory, the failure is a false alarm — ignore it

      ## `_build/` and `deps/`

      Compile artifacts. Never commit. Already in `.gitignore`.
      """
    },
    %{
      title: "ExCalibur: Valid Sandbox Commands",
      tags: ["sandbox", "commands", "tools", "run_sandbox"],
      importance: 5,
      body: """
      # ExCalibur: Valid Sandbox Commands

      The `run_sandbox` tool only accepts commands with these prefixes:

      - `mix test` — run the full suite or a specific file
      - `mix credo` — static analysis
      - `mix dialyzer` — type checking (slow, use sparingly)
      - `mix excessibility` — accessibility audit of LiveView snapshots
      - `mix format` — auto-format Elixir source files
      - `mix deps.audit` — check for vulnerable dependencies

      Anything else returns: `Command not allowed. Must start with: ...`

      ## Valid examples

      ```
      mix test
      mix test test/ex_calibur/board_test.exs
      mix test --only integration
      mix credo --all
      mix excessibility
      mix format
      mix format --check-formatted
      ```

      ## Invalid — do not try these

      ```
      mix test check           # not a mix task
      mix test --no-test       # not a valid flag
      mix format --check       # not a valid flag (use --check-formatted)
      git status               # not in allowlist; use git_commit/git_push tools
      ```
      """
    },
    %{
      title: "ExCalibur: Self-Improvement Pipeline",
      tags: ["pipeline", "self-improvement", "workflow", "agents", "quests"],
      importance: 5,
      body: """
      # ExCalibur: Self-Improvement Pipeline

      Two overlapping systems handle self-improvement.

      ## SI: Analyst Sweep — scheduled every 4 hours (two steps)

      **Step 1: SI: Static Analysis** — runs deterministic tools, outputs raw results
      - Runs `mix credo --all` and `mix deps.audit`
      - Uses a fast/cheap model — no reasoning, just tool execution and formatted output
      - Outputs structured findings for the next step to analyze

      **Step 2: SI: Product Analyst Sweep** — analyzes findings, files GitHub issues
      - Receives the static analysis output from Step 1 as context
      - Cross-references against the credo baseline lore entry
      - Files at most 3 high-value issues (quality > quantity)
      - Uses journeyman model (devstral) for reliable analysis

      ## Self-Improvement Loop — source-triggered by GitHub issues labeled `self-improvement`

      1. SI: PM Triage — evaluates issue, writes implementation plan
      2. SI: Code Writer — implements in a worktree, opens PR
      3. SI: Code Reviewer — reviews correctness and patterns (verdict gate)
      4. SI: QA — runs tests, issues a verdict (verdict gate)
      5. SI: UX Designer — runs `mix excessibility`, checks accessibility
      6. SI: PM Merge Decision — auto-merge or escalate to CTO

      ## Key workflow rules

      - Static Analysis outputs raw results only — no decisions
      - Product Analyst reads lore before filing any issues
      - Do NOT file issues for anything in the credo baseline lore entry
      - UX Designer uses `mix excessibility` — not `mix test` or `mix format`
      """
    },
    %{
      title: "ExCalibur: Available LLM Models",
      tags: ["models", "ollama", "llm", "fallback", "performance"],
      importance: 4,
      body: """
      # ExCalibur: Available LLM Models

      ## Ollama (local)

      **`ministral-3:8b`** — fast, primary model
      - Good: reading code, simple analysis, quick verdicts
      - Weak: long tool-call chains (can time out ~125s)
      - Assigned to: apprentice/quick perspectives

      **`devstral-small-2:24b`** — reliable code model
      - Good: multi-iteration tool-calling, code writing, detailed analysis
      - Assigned to: journeyman/thorough perspectives
      - Used as the fallback chain model

      **`gemma3:4b`** — installed but NOT in fallback chain
      - Breaks on tool-call conversations (strict alternating user/assistant roles)
      - Safe for plain `complete` calls only

      **Dead models** (return 404, not installed): `phi4-mini`, `llama3:8b`

      ## Fallback chain

      `config :ex_calibur, :model_fallback_chain, ["devstral-small-2:24b"]`

      ## Claude (Anthropic)

      Available via model IDs `claude_haiku`, `claude_sonnet`, `claude_opus`.
      Used for higher-stakes tasks configured to use the Claude provider.
      """
    },
    %{
      title: "ExCalibur: Credo Baseline",
      tags: ["credo", "code-quality", "baseline", "known-issues"],
      importance: 5,
      body: """
      # ExCalibur: Credo Baseline

      `mix credo --all` reports 46 pre-existing refactoring opportunities. Do NOT file GitHub issues
      for any of these. They are accepted technical debt. Only file issues for NEW problems
      introduced by recent changes.

      ## Full baseline — do not file issues for these

      ### ExCalibur.LLM.Claude (lib/ex_calibur/llm/claude.ex)
      - execute_tools_with_log — nested depth 4 (line 196)
      - execute_tools_with_log — cyclomatic complexity 14 (line 132)
      - run_agent_loop — nested depth 3 (line 114)

      ### ExCalibur.LLM.Ollama (lib/ex_calibur/llm/ollama.ex)
      - execute_or_intercept_tool — nested depth 3 (line 236)
      - run_tool_loop — nested depth 3 (line 132)
      - run_tool_loop — arity 10 (lines 97, 104)
      - run_tool_loop — cyclomatic complexity 10 (line 104)
      - execute_tool_calls — nested depth 3 (line 204)

      ### ExCalibur.StepRunner (lib/ex_calibur/step_runner.ex)
      - run — cyclomatic complexity 19 (line 212)
      - run — nested depth 4 (lines 205, 107)
      - run — cyclomatic complexity 16 (line 173)
      - run — cyclomatic complexity 10 (line 79)
      - run — nested depth 3 (line 244)
      - run_artifact — nested depth 4 (line 664)
      - gather_reflect_context — nested depth 3 (line 603)
      - parse_artifact — cyclomatic complexity 13 (line 737)

      ### ExCalibur.QuestRunner (lib/ex_calibur/quest_runner.ex)
      - do_run — cyclomatic complexity 29 (line 51)

      ### ExCalibur.Board (lib/ex_calibur/board.ex)
      - install — cyclomatic complexity 20 (line 211)
      - install — nested depth 4 (line 272)
      - all_with_status — nested depth 3 (line 158)
      - all_with_status — cyclomatic complexity 13 (line 113)

      ### ExCaliburWeb LiveViews
      - GuildHallLive.handle_event — cyclomatic complexity 15 (line 848)
      - GuildHallLive.handle_event — cyclomatic complexity 10 (line 807)
      - GuildHallLive.mount_guild_hall — nested depth 4 (line 35)
      - GuildHallLive.to_unified — cyclomatic complexity 13 (line 92)
      - SettingsLive.handle_event — nested depth 3 (line 64)
      - QuestsLive.handle_event — nested depth 3 (line 164)
      - QuestsLive.handle_event — cyclomatic complexity 12 (lines 276, 347)
      - QuestsLive.build_schedule_from_params — cyclomatic complexity 18 (line 1515)
      - LodgeLive.handle_event — nested depth 3 (line 195)
      - LodgeLive.load_dev_team_status — nested depth 3 (line 429)
      - TownSquareLive.install_quests — nested depth 3 (line 191)
      - GrimoireLive.load_run_stats — nested depth 3 (line 124)

      ### Other modules
      - TrustScorer.record_run — nested depth 4 (lib/ex_calibur/trust_scorer.ex:26)
      - Tools.AnalyzeVideo.call — nested depth 4 (lib/ex_calibur/tools/analyze_video.ex:66)
      - Sources.LodgeWatcher.fetch — cyclomatic complexity 14 (lib/ex_calibur/sources/lodge_watcher.ex:18)
      - Tools.EditFile.call — nested depth 3 (lib/ex_calibur/tools/edit_file.ex:30)
      - Sources.MediaSource.list_videos — nested depth 3 (lib/ex_calibur/sources/media_source.ex:58)
      - Sources.ObsidianWatcher.fetch — nested depth 3 (lib/ex_calibur/sources/obsidian_watcher.ex:30)
      - Sources.EmailSource.fetch — nested depth 3 (lib/ex_calibur/sources/email_source.ex:24)
      - Lore.write_artifact — nested depth 3 (lib/ex_calibur/lore.ex:67)
      - ContextProviders.QuestHistory.build — nested depth 3 (lib/ex_calibur/context_providers/quest_history.ex:35)
      - ContextProviders.MemberStats.build — nested depth 3 (lib/ex_calibur/context_providers/member_stats.ex:30)

      ## What IS worth filing issues for

      - New credo issues not in this list (introduced by a recent commit)
      - `length/1` checks in tests that can be replaced with `!= []`
      - Specific bugs with reproduction steps
      """
    }
  ]

  defp seed_lore do
    existing_titles =
      Repo.all(
        from(e in LoreEntry,
          where: e.title in ^Enum.map(@lore_entries, & &1.title),
          select: e.title
        )
      )

    # Delete stale entries so they are always recreated fresh from the seed.
    if existing_titles != [] do
      Repo.delete_all(from(e in LoreEntry, where: e.title in ^existing_titles))
    end

    Enum.each(@lore_entries, fn entry ->
      ExCalibur.Lore.create_entry(Map.put(entry, :source, "manual"))
    end)
  end

  defp create_sweep_quest(analysis_step, sweep_step) do
    Quests.create_quest(%{
      name: "SI: Analyst Sweep",
      description:
        "Every 4 hours: run static analysis tools, then have the Product Analyst review the findings and file high-value GitHub issues.",
      trigger: "scheduled",
      schedule: "0 */4 * * *",
      steps: [
        %{"step_id" => analysis_step.id, "order" => 1},
        %{"step_id" => sweep_step.id, "order" => 2}
      ],
      status: "active"
    })
  end
end
