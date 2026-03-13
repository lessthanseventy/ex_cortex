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
    "SI: Product Analyst Sweep",
    "SI: Codebase Health Scan",
    "SI: Feature & Opportunity Scan",
    "SI: Backlog Synthesis",
    "SI: Issue Filing"
  ]

  @si_quest_names ["Self-Improvement Loop", "SI: Analyst Sweep"]

  def seed(opts \\ %{}) do
    repo = Map.get(opts, :repo, "")
    cleanup()

    with {:ok, source} <- create_source(repo),
         {:ok, steps} <- create_steps(),
         {:ok, quest} <- create_quest(source, steps),
         {:ok, sweep_steps} <- create_sweep_steps(),
         {:ok, sweep_quest} <- create_sweep_quest(sweep_steps) do
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
        2. Run `mix credo --all` via run_sandbox. Report any warnings introduced by this change.
        3. Issue your verdict: pass (all tests pass, no new credo warnings), warn (tests pass but minor concerns), fail (test failures or new credo errors).
        """,
        trigger: "manual",
        output_type: "verdict",
        dangerous_tool_mode: "intercept",
        max_tool_iterations: 10,
        loop_mode: "reflect",
        max_iterations: 3,
        loop_tools: ["run_sandbox", "read_file"],
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

  defp create_sweep_steps do
    results = [
      create_static_analysis_step(),
      create_health_scan_step(),
      create_opportunity_scan_step(),
      create_backlog_synthesis_step(),
      create_issue_filing_step()
    ]

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, s} -> s end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_static_analysis_step do
    Quests.create_step(%{
      name: "SI: Static Analysis",
      description: """
      Call run_sandbox("mix credo --all"). Then call run_sandbox("mix deps.audit"). Then call run_sandbox("mix test").
      Output the raw results. Nothing else.

      Do not greet. Do not explain. Do not make recommendations. Do not ask questions.
      Your entire response must be the raw tool output in this format:

      ## Credo Findings
      <exact credo output>

      ## Dependency Audit
      <exact deps.audit output>

      ## Test Results
      <exact mix test output>

      If you output anything other than these three sections, you have failed this task.
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "execute",
      max_tool_iterations: 5,
      loop_tools: ["run_sandbox"],
      roster: [%{"who" => "journeyman", "preferred_who" => "QA / Test Writer", "how" => "solo", "when" => "sequential"}]
    })
  end

  defp create_health_scan_step do
    Quests.create_step(%{
      name: "SI: Codebase Health Scan",
      description: """
      You are the Code Auditor performing a codebase health scan.

      Your context includes the static analysis output from the previous step.

      ## Your job

      Systematically scan lib/ and test/ to identify concrete health issues. You are looking for things
      that are actually broken or risky — not style preferences.

      Work through these categories:

      **Test coverage gaps**
      - list_files("lib/**/*.ex") then list_files("test/**/*.exs")
      - For each significant module in lib/, check whether a corresponding test file exists
      - Flag modules with substantial logic and no tests

      **Error handling gaps**
      - Read files flagged by credo or that look risky (large files, external integrations)
      - Look for missing rescue clauses on DB calls, HTTP calls, file I/O
      - Look for bare pattern matches that could crash on unexpected input

      **TODO/FIXME comments**
      - These are deferred work explicitly flagged by developers — worth tracking

      **Functions over ~60 lines**
      - Large functions are hard to test and maintain; note them with file:line

      ## Output format

      Write a structured findings report. For each finding:
      - Category (test gap / error handling / TODO / complexity)
      - File path and function name
      - One sentence explaining the specific issue

      Do NOT file any GitHub issues. Do NOT make recommendations. Just report what you found with evidence.
      If credo was clean and tests all passed and you find nothing notable, say so — that's a valid result.
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "execute",
      max_tool_iterations: 20,
      loop_tools: ["read_file", "list_files"],
      roster: [%{"who" => "journeyman", "preferred_who" => "Code Auditor", "how" => "solo", "when" => "sequential"}]
    })
  end

  defp create_opportunity_scan_step do
    Quests.create_step(%{
      name: "SI: Feature & Opportunity Scan",
      description: """
      You are the Product Analyst performing an opportunity scan.

      Your context includes the health scan findings from the previous step.

      ## Your job — a DIFFERENT lens than the Code Reviewer

      You are NOT looking for bugs or code quality issues. You are thinking about product value:
      what should this app be able to do that it currently can't, or does poorly?

      Work through these angles:

      **Unfinished or partially-implemented features**
      - query_lore with tags ["self-improvement", "project"] to understand what's been in progress
      - Look at Board templates (lib/ex_calibur/board/) — are any patterns missing or thin?
      - Read lib/ex_calibur/self_improvement/ — is the pipeline complete or are there gaps?

      **User experience gaps**
      - Think about the pages: Lodge, Town Square, Guild Hall, Quests, Grimoire, Library, Settings
      - Is there functionality that would obviously be useful but is absent?

      **Integration opportunities**
      - What external tools or workflows could this app connect to that it doesn't yet?

      **Recurring friction**
      - query_lore broadly — are there lore entries describing known pain points or workarounds?

      ## Output format

      Write a list of opportunities. For each:
      - What's missing or incomplete
      - Why it would matter (user impact or developer impact)
      - Where in the codebase it would live (rough file/module area)
      - Rough effort: small (hours) / medium (days) / large (week+)

      Do NOT file GitHub issues. Do NOT repeat health scan findings (those are code quality, not features).
      Aim for 3–8 genuine opportunities. If you find nothing notable, say so.
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "execute",
      max_tool_iterations: 20,
      loop_tools: ["read_file", "list_files", "query_lore"],
      roster: [%{"who" => "journeyman", "preferred_who" => "Product Analyst", "how" => "solo", "when" => "sequential"}]
    })
  end

  defp create_backlog_synthesis_step do
    Quests.create_step(%{
      name: "SI: Backlog Synthesis",
      description: """
      You are the Project Manager synthesizing the team's findings into an actionable shortlist.

      Your context includes the health scan findings AND the opportunity scan from the previous steps.

      ## Your job

      **Step 1: Check the existing backlog**
      Search GitHub for open issues. Understand what's already being tracked.
      Identify any open issues that appear stale (no activity, no longer relevant) — note them but don't close them here.

      **Step 2: Synthesize**
      From the health scan + opportunity scan, identify the highest-value items to act on.
      Consider: real impact vs effort, whether it's already tracked, whether it blocks other work.

      **Step 3: Produce the shortlist**
      Pick 3–5 items maximum. For each item, write:

      ---
      APPROVED: <title>
      Type: bug | feature | improvement | tech-debt
      Source: health-scan | opportunity-scan
      Why now: <one sentence — what's the cost of not doing this>
      Effort: small | medium | large
      ---

      Items NOT on this list will not be filed. Be ruthless — only include things that are genuinely worth a
      developer's time. Vague suggestions, style improvements, and anything already tracked should be excluded.

      End your response with the shortlist only. Do not include a summary or recommendations beyond the list.
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "execute",
      max_tool_iterations: 15,
      loop_tools: ["search_github", "query_lore"],
      roster: [%{"who" => "journeyman", "preferred_who" => "Backlog Manager", "how" => "solo", "when" => "sequential"}]
    })
  end

  defp create_issue_filing_step do
    Quests.create_step(%{
      name: "SI: Issue Filing",
      description: """
      You are the Product Analyst filing GitHub issues from the PM's approved shortlist.

      Your context includes the PM's shortlist from the Backlog Synthesis step.
      Look for lines starting with "APPROVED:" — those are the items to file.

      ## For each APPROVED item

      1. Search GitHub to confirm no open issue already covers this exact topic.
         If a duplicate exists, skip this item and note it.
      2. If no duplicate: call create_github_issue with:
         - title: the APPROVED title (clear, specific, actionable)
         - body: describe the problem concretely — what is broken or missing, where in the codebase,
           what the impact is, and what a fix would look like. Be specific enough that a developer
           can start working without needing to ask questions.
         - labels: ["self-improvement"]

      ## Quality bar for issue bodies

      A good issue body answers:
      - What exactly is the problem? (not "X could be better" — "X does Y when it should do Z")
      - Where is it? (file path, function name if applicable)
      - Why does it matter? (what breaks, what's risky, what's blocked)
      - What would done look like? (acceptance criteria)

      File each APPROVED item as a separate issue. When done, summarize what was filed and what was skipped.
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "intercept",
      max_tool_iterations: 20,
      loop_tools: ["search_github", "create_github_issue"],
      roster: [%{"who" => "journeyman", "preferred_who" => "Product Analyst", "how" => "solo", "when" => "sequential"}]
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

      ## SI: Analyst Sweep — scheduled every 4 hours (five steps)

      A full team runs every 4 hours to find and file high-quality improvement issues.

      **Step 1: SI: Static Analysis** (QA / Test Writer)
      - Runs `mix credo --all`, `mix deps.audit`, `mix test`
      - Outputs raw results only — no interpretation

      **Step 2: SI: Codebase Health Scan** (Code Auditor)
      - Reads static analysis output, then browses lib/ and test/
      - Looks for: test coverage gaps, error handling gaps, TODO comments, large functions
      - Outputs a structured findings report with file:line evidence
      - Does NOT file issues — just reports

      **Step 3: SI: Feature & Opportunity Scan** (Product Analyst)
      - Different lens: product value, not code quality
      - Looks for missing features, incomplete functionality, UX gaps, integration opportunities
      - Queries lore to understand what's been deferred or worked on
      - Outputs an opportunity list with effort estimates
      - Does NOT file issues — just reports

      **Step 4: SI: Backlog Synthesis** (Backlog Manager)
      - Receives health scan AND opportunity scan findings
      - Searches GitHub to understand existing open issues
      - Synthesizes into a ranked shortlist of 3–5 items approved for filing
      - This is the gate — nothing gets filed without PM approval

      **Step 5: SI: Issue Filing** (Product Analyst)
      - Receives only the PM's approved shortlist
      - Does a final duplicate check per item, then files each as a GitHub issue
      - Issues go to the self-improvement label for the SI Loop to pick up

      ## Self-Improvement Loop — source-triggered by GitHub issues labeled `self-improvement`

      1. SI: PM Triage — evaluates issue, writes implementation plan or rejects
      2. SI: Code Writer — implements in a worktree, opens PR
      3. SI: Code Reviewer — reviews correctness and patterns (verdict gate)
      4. SI: QA — runs tests, issues a verdict (verdict gate)
      5. SI: UX Designer — runs `mix excessibility`, checks accessibility
      6. SI: PM Merge Decision — auto-merge low-risk changes or escalate

      ## Key workflow rules

      - Static Analysis outputs raw results only — no decisions, no interpretation
      - Health Scan and Opportunity Scan report findings — they do NOT file issues
      - Only the PM's approved shortlist gets filed (Step 4 → Step 5)
      - Issue Filing does a final duplicate search before each create_github_issue call
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

  defp create_sweep_quest(sweep_steps) do
    step_entries =
      sweep_steps
      |> Enum.with_index(1)
      |> Enum.map(fn {step, order} -> %{"step_id" => step.id, "order" => order} end)

    Quests.create_quest(%{
      name: "SI: Analyst Sweep",
      description:
        "Every 4 hours: static analysis → codebase health scan → feature opportunity scan → PM backlog synthesis → issue filing.",
      trigger: "scheduled",
      schedule: "0 */4 * * *",
      steps: step_entries,
      status: "active"
    })
  end
end
