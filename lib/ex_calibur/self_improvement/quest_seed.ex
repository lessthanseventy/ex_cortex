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

  # Note: "SI: Static Analysis" stays in the cleanup list so it's removed if present from old seeds

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
      create_health_scan_step(),
      create_opportunity_scan_step(),
      create_backlog_synthesis_step(),
      create_issue_filing_step(),
      create_product_analyst_sweep_step()
    ]

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, s} -> s end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_product_analyst_sweep_step do
    Quests.create_step(%{
      name: "SI: Product Analyst Sweep",
      description: """
      Product Analyst performs a comprehensive sweep of the codebase and product landscape.

      ## Tools: read_file, query_lore, search_github

      ## Workflow:
      1. Query lore for project identity and domain
      2. Read key files to understand current state
      3. Search GitHub for existing issues
      4. Identify gaps and opportunities

      ## Output:
      - Summary of findings
      - Recommendations for improvements
      - Prioritized list of action items
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "execute",
      max_tool_iterations: 10,
      loop_tools: ["read_file", "query_lore", "search_github"],
      roster: [%{"who" => "journeyman", "preferred_who" => "Product Analyst", "how" => "solo", "when" => "sequential"}]
    })
  end

  defp create_health_scan_step do
    Quests.create_step(%{
      name: "SI: Codebase Health Scan",
      description: """
      You are the Code Auditor performing a scheduled codebase health scan.

      ## YOUR TOOLS: run_sandbox and read_file ONLY.
      There is no list_files tool. Do not attempt to call it.

      ## Required steps — do them in this order:

      **1. Run static analysis (first two calls)**
      - run_sandbox("mix credo --all")
      - run_sandbox("mix test")

      **2. Read at most 3 targeted files (based on credo output)**
      Read only files that credo flagged or that match these high-value targets:
      - lib/ex_calibur/step_runner.ex
      - lib/ex_calibur/quest_runner.ex
      - lib/ex_calibur/llm/ollama.ex
      Do NOT read charter files, Ecto schema files, or watcher files.

      **3. Write your findings report immediately after the reads**

      Format each finding as:
      - [Category: test gap | error handling | TODO | complexity] File:line — one sentence

      Do NOT file issues. Do NOT make recommendations. 3–8 findings max.
      If credo and tests are clean and you see nothing notable, say so in one paragraph.
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "execute",
      max_tool_iterations: 6,
      loop_tools: ["run_sandbox", "read_file"],
      roster: [%{"who" => "journeyman", "preferred_who" => "Code Auditor", "how" => "solo", "when" => "sequential"}]
    })
  end

  defp create_opportunity_scan_step do
    Quests.create_step(%{
      name: "SI: Feature & Opportunity Scan",
      description: """
      You are the Product Analyst performing an opportunity scan.

      Your context includes the health scan findings from the previous step.

      ## FIRST: Ground yourself in what ExCalibur actually is

      Before doing anything else, call query_lore with tags ["project"] to understand the project.
      ExCalibur is a Phoenix LiveView web application for AI agent orchestration. It has these pages:
      Lodge, Town Square, Guild Hall, Quests, Grimoire, Library, Settings, Evaluate.
      It works with guilds (agent teams), members (roles), quests (pipelines), sources, and lore entries.

      **You are looking for improvements to THIS specific app — ExCalibur.**
      Do NOT suggest features for game engines, audio systems, physics engines, or any other domain.
      Every suggestion must relate to something you can find evidence for in lib/ or test/.

      ## Your job — a DIFFERENT lens than the Code Auditor

      You are NOT looking for bugs or code quality issues. You are thinking about product value:
      what should ExCalibur be able to do that it currently can't, or does poorly?

      ## Tools available: read_file, query_lore ONLY
      Do NOT call list_files — it is not available in this step and will waste iterations.
      You already know which files to read from the instructions below.

      Work through these angles — each requires reading actual code first:

      **Unfinished or partially-implemented features**
      - query_lore with tags ["self-improvement", "project"] to understand what's been in progress
      - Read lib/ex_calibur/self_improvement/quest_seed.ex — is the SI pipeline complete or are there gaps?
      - Read lib/ex_calibur/board/generation.ex — are quest templates missing for common patterns?

      **User experience gaps**
      - Read lib/ex_calibur_web/live/quests_live.ex to understand what the Quests page does
      - Read lib/ex_calibur_web/live/lodge_live.ex to understand the Lodge page
      - Is there functionality that would obviously be useful but is absent from these pages?

      **Integration opportunities**
      - query_lore broadly for entries describing known pain points or workarounds
      - What integrations does the codebase partially implement but not finish?

      ## Output format

      Write a list of opportunities grounded in code evidence. For each:
      - What's missing or incomplete (cite the file you read)
      - Why it would matter (user impact or developer impact)
      - Where in the codebase it would live (exact file/module)
      - Rough effort: small (hours) / medium (days) / large (week+)

      ## IMPORTANT: Read at most 8 files total, then write your output.

      Do not spend all your iterations reading files. After 5-6 file reads, stop and write your findings.
      You will hit a hard iteration limit — if you haven't written your output by then, it will be lost.

      Do NOT suggest features you can't tie to actual code you read.
      Do NOT repeat health scan findings (those are code quality, not features).
      Aim for 3–8 genuine opportunities. If you find nothing notable after reading the code, say so.
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "execute",
      max_tool_iterations: 10,
      loop_tools: ["read_file", "query_lore"],
      roster: [%{"who" => "journeyman", "preferred_who" => "Product Analyst", "how" => "solo", "when" => "sequential"}]
    })
  end

  defp create_backlog_synthesis_step do
    Quests.create_step(%{
      name: "SI: Backlog Synthesis",
      description: """
      You are the Project Manager synthesizing the team's findings into an actionable shortlist.

      Your context includes the health scan findings AND the opportunity scan from the previous steps.

      ## Step 1: Check existing open issues (one tool call)

      Call search_github with query "existing issues" and label "self-improvement" to see what is already tracked.
      If it returns empty (`[]`), that is fine — it means no issues are open yet. Continue.
      Use the results to avoid duplicating anything already open.

      ## Step 2: Synthesize and produce the shortlist

      From the health scan + opportunity scan, pick 3–5 high-value items not already tracked.
      Exclude: vague suggestions, style improvements, credo baseline noise, anything already open.

      For each approved item write EXACTLY this format (the next step parses it literally):

      ---
      APPROVED: <specific, actionable title>
      Type: bug | feature | improvement | tech-debt
      Source: health-scan | opportunity-scan
      Why now: <one sentence — cost of not doing this>
      Effort: small | medium | large
      Body hint: <2-3 sentences describing the problem, file path if known, what done looks like>
      ---

      Output the shortlist. Nothing else after it.
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "execute",
      max_tool_iterations: 5,
      loop_tools: ["search_github"],
      roster: [%{"who" => "journeyman", "preferred_who" => "Backlog Manager", "how" => "solo", "when" => "sequential"}]
    })
  end

  defp create_issue_filing_step do
    Quests.create_step(%{
      name: "SI: Issue Filing",
      description: """
      You are the Product Analyst filing GitHub issues.

      ⚠️ YOU HAVE EXACTLY ONE TOOL: create_github_issue
      DO NOT CALL: list_files, run_sandbox, read_file, search_github, or any other tool.
      Those tools do not exist in this step. Calling them will waste your iterations and fail the task.

      ## Your task

      1. Scan your context for blocks starting with "APPROVED:" — each is an issue to file.
         If none exist, pick the 3 most actionable items from any analysis in your context.

      2. For each item, immediately call create_github_issue:
         - title: the APPROVED title
         - body: 3–5 sentences — what is wrong or missing, which file/module, why it matters, what done looks like
         - labels: ["self-improvement"]

      3. When done, output: "Filed N issues: [title1], [title2], ..."

      Call create_github_issue immediately. Do not call any other tool first.
      **If you finish without calling create_github_issue at least once, you have failed.**
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "intercept",
      max_tool_iterations: 20,
      loop_tools: ["create_github_issue"],
      roster: [%{"who" => "journeyman", "preferred_who" => "Product Analyst", "how" => "solo", "when" => "sequential"}]
    })
  end

  @lore_entries [
    %{
      title: "ExCalibur: What This Project Is",
      tags: ["project", "identity", "domain", "overview"],
      importance: 5,
      body: """
      # ExCalibur: What This Project Is

      ExCalibur is a **Phoenix LiveView web application** for AI agent orchestration and self-improvement.
      It is a standalone app that provides a UI and pipeline engine for running teams of AI agents.

      ## What ExCalibur IS

      - A web UI for configuring and running AI agent pipelines
      - An orchestration layer for calling Ollama (local LLMs) and Claude (Anthropic)
      - A self-improvement system where AI agents work on ExCalibur itself
      - A guild/member/quest framework: guilds are agent teams, members are roles, quests are pipelines

      ## Key pages

      - **Lodge** (`/lodge`) — dashboard showing quest outputs, pinned cards, proposal review
      - **Town Square** (`/town-square`) — charter browser and guild installer
      - **Guild Hall** (`/guild-hall`) — browse/manage guild members
      - **Quests** (`/quests`) — quest planner, step configuration
      - **Grimoire** (`/grimoire`) — lore browser; view/search lore entries
      - **Library** (`/library`) — source blueprint browser
      - **Evaluate** (`/evaluate`) — run text against a guild and see verdicts
      - **Settings** (`/settings`) — Ollama URL, API keys, default repo, feature flags

      ## Key modules

      - `ExCalibur.QuestRunner` — runs quests step by step
      - `ExCalibur.StepRunner` — runs a single step against members
      - `ExCalibur.Lodge` — lodge card management
      - `ExCalibur.Lore` — lore entry storage and retrieval
      - `ExCalibur.Sources.*` — source workers (GitHub issues, webhooks, feeds, etc.)
      - `ExCalibur.Tools.*` — tool implementations (run_sandbox, create_github_issue, etc.)
      - `ExCalibur.Charters.*` — pre-built guild definitions
      - `ExCalibur.SelfImprovement.*` — SI pipeline seeding

      ## What ExCalibur is NOT

      - Not a game engine
      - Not an audio or physics system
      - Not a mobile app
      - Not a data pipeline or ETL tool

      If you are filing issues or suggesting features, they MUST relate to the modules and pages above.
      Any suggestion about game engines, audio systems, collision detection, gamepads, etc. is wrong —
      reject it immediately as a hallucination.
      """
    },
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

      ## SI: Analyst Sweep — scheduled every 4 hours (four steps)

      A full team runs every 4 hours to find and file high-quality improvement issues.

      **Step 1: SI: Codebase Health Scan** (Code Auditor)
      - Runs `mix credo --all` and `mix test` inline to get fresh static analysis data
      - Then reads up to 6 targeted files guided by the credo output
      - Looks for: test coverage gaps, error handling gaps, TODO comments, large functions
      - Outputs a structured findings report with file:line evidence
      - Does NOT file issues — just reports

      **Step 2: SI: Feature & Opportunity Scan** (Product Analyst)
      - Different lens: product value, not code quality
      - Looks for missing features, incomplete functionality, UX gaps, integration opportunities
      - Queries lore to understand what's been deferred or worked on
      - Outputs an opportunity list with effort estimates
      - Does NOT file issues — just reports

      **Step 3: SI: Backlog Synthesis** (Backlog Manager)
      - Receives health scan AND opportunity scan findings
      - Calls search_github once with label "self-improvement" to check existing open issues
      - Synthesizes into a ranked shortlist of 3–5 items approved for filing
      - Outputs each item as an APPROVED: block with Type/Source/Why now/Effort/Body hint fields
      - This is the gate — nothing gets filed without PM approval

      **Step 4: SI: Issue Filing** (Product Analyst)
      - Receives the PM's APPROVED: shortlist (duplicate check already done by Backlog Synthesis)
      - Calls create_github_issue once per APPROVED item — no per-item search needed
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
      - Backlog Synthesis does the duplicate check (one search_github call); Issue Filing trusts it
      - Issue Filing calls create_github_issue directly — no per-item search, no hesitation
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

  defp create_sweep_quest(sweep_steps) do
    step_entries =
      sweep_steps
      |> Enum.with_index(1)
      |> Enum.map(fn {step, order} -> %{"step_id" => step.id, "order" => order} end)

    Quests.create_quest(%{
      name: "SI: Analyst Sweep",
      description:
        "Every 4 hours: codebase health scan (with inline static analysis) → feature opportunity scan → PM backlog synthesis → issue filing.",
      trigger: "scheduled",
      schedule: "0 */4 * * *",
      steps: step_entries,
      status: "active"
    })
  end
end
