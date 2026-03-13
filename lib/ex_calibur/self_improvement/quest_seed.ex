defmodule ExCalibur.SelfImprovement.QuestSeed do
  @moduledoc "Seeds the self-improvement pipeline — called when Dev Team charter is installed."

  import Ecto.Query

  alias ExCalibur.Lore.LoreEntry
  alias ExCalibur.Quests
  alias ExCalibur.Quests.Quest
  alias ExCalibur.Quests.Step
  alias ExCalibur.Repo
  alias ExCalibur.Sources.Source

  # Old names kept here so cleanup deletes them on re-seed
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
    "SI: Issue Filing",
    "SI: Backlog & Issue Filing"
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

        If PM Triage decided REJECT, output exactly: SKIPPED: PM rejected this issue.
        Do nothing else.

        ## MANDATORY workflow — follow in order, every step required:

        **Step 1 — setup_worktree(issue_id: "<N>")**
        Do this FIRST. It returns a worktree path like `/home/andrew/projects/ex_calibur/.worktrees/N`.
        Save this path — you MUST pass it as `working_dir` to EVERY subsequent tool call.
        NEVER write, commit, or push without working_dir. NEVER use the main repo path.

        **Step 2 — read_file(path: "...", working_dir: "<worktree_path>")**
        Read the files relevant to the PM's plan. Always pass working_dir.

        **Step 3 — write_file or edit_file(path: "...", ..., working_dir: "<worktree_path>")**
        Make the minimal focused change from the PM's plan. No scope creep.

        **Step 4 — run_sandbox("mix test")**
        Must pass. Fix any test failures before continuing.

        **Step 5 — run_sandbox("mix credo --all")**
        Fix any NEW credo warnings your change introduced.

        **Step 6 — git_commit(files: [...], message: "fix: ...(closes #N)", working_dir: "<worktree_path>")**
        Always pass working_dir. Commits go to the branch, never main.

        **Step 7 — git_push(branch: "self-improve/N", working_dir: "<worktree_path>")**

        **Step 8 — open_pr(title: "...", body: "...", working_dir: "<worktree_path>")**
        The body must be a full GitHub PR description in markdown:
        - What changed and why
        - Which files were modified
        - How to test the change
        - "Closes #N" to auto-close the issue

        **Step 9 — output:**
        PR: <url>
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
        description: """
        You are the Project Manager making the final merge decision.

        Review the QA and UX verdicts in your context.

        ## If Code Writer output "SKIPPED":
        Output: SKIPPED — no PR to merge.

        ## If QA verdict is "fail":
        Output: BLOCKED — QA failed. Do not merge.

        ## If QA verdict is "pass" or "warn" (with acceptable warnings):
        1. Find the PR number in your context (look for "PR: https://..." or "#N").
        2. Call merge_pr with the PR number and method: "squash".
        3. Output: MERGED PR #N via squash.

        ## If in doubt:
        Output: ESCALATE — needs human review. Summarize why in one sentence.
        """,
        trigger: "manual",
        output_type: "freeform",
        dangerous_tool_mode: "execute",
        max_tool_iterations: 5,
        loop_tools: ["merge_pr"],
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
      create_backlog_and_file_step()
    ]

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, s} -> s end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_health_scan_step do
    Quests.create_step(%{
      name: "SI: Codebase Health Scan",
      description: """
      You are the Code Auditor performing a codebase health scan.

      The `mix credo --all` and `mix test` results are provided above.
      The key source files are also provided above for reference.
      You do not need to call any tools — all data is already in context.

      Write your findings report now. Format each finding as:
      - [Category: test gap | error handling | TODO | complexity | credo] File:line — one sentence

      3–8 findings max. If credo and tests are clean and files look solid, say so in one paragraph.
      Do NOT file issues. Do NOT make recommendations. Write the report and stop.
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "execute",
      loop_tools: [],
      context_providers: [
        %{"type" => "sandbox", "commands" => ["mix credo --all", "mix test"], "label" => "## Static Analysis Results"},
        %{
          "type" => "file_reader",
          "files" => ["lib/ex_calibur/step_runner.ex", "lib/ex_calibur/quest_runner.ex", "lib/ex_calibur/llm/ollama.ex"],
          "label" => "## Key Source Files",
          "max_bytes_per_file" => 3000
        },
        %{"type" => "app_telemetry", "window_hours" => 6}
      ],
      roster: [%{"who" => "journeyman", "preferred_who" => "Code Auditor", "how" => "solo", "when" => "sequential"}]
    })
  end

  defp create_opportunity_scan_step do
    Quests.create_step(%{
      name: "SI: Feature & Opportunity Scan",
      description: """
      You are the Product Analyst performing an opportunity scan.

      The project context, health scan findings, and key source files are all provided above.
      You do not need to call any tools — all data is already in context.

      ## What you are looking for

      Product value — NOT code quality. What should ExCalibur be able to do that it currently
      can't, or does poorly? Every suggestion must relate to the files and modules shown above.

      ExCalibur is a Phoenix LiveView app for AI agent orchestration: guilds (agent teams),
      members (roles), quests (pipelines), sources, lore, lodge. Do NOT suggest features for
      unrelated domains (no game engines, no audio, no physics).

      ## Output format (write this now)

      For each opportunity you identify from the files above:
      - What's missing or incomplete (cite the exact file/module)
      - Why it matters (user impact)
      - Where the fix would live
      - Effort: small | medium | large

      3–6 opportunities. Do NOT repeat health scan findings.
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "execute",
      loop_tools: [],
      context_providers: [
        %{"type" => "lore", "tags" => ["project", "self-improvement", "pipeline"], "limit" => 3, "sort" => "top"},
        %{
          "type" => "file_reader",
          "files" => [
            "lib/ex_calibur/self_improvement/quest_seed.ex",
            "lib/ex_calibur_web/live/quests_live.ex",
            "lib/ex_calibur_web/live/lodge_live.ex",
            "lib/ex_calibur/board/generation.ex"
          ],
          "label" => "## Source Files for Analysis",
          "max_bytes_per_file" => 2500
        }
      ],
      roster: [%{"who" => "journeyman", "preferred_who" => "Product Analyst", "how" => "solo", "when" => "sequential"}]
    })
  end

  defp create_backlog_and_file_step do
    Quests.create_step(%{
      name: "SI: Backlog & Issue Filing",
      description: """
      You are the Project Manager. Your job is to synthesize findings from this sweep and
      immediately file approved items as GitHub issues — no handoff, no intermediate list.

      The health scan findings, opportunity scan, and currently open GitHub issues are all
      provided above in context.

      ## Ignore these — they are expected test environment noise, not real bugs

      - Any `Req.TransportError` or `econnrefused` errors (Nextcloud is not running in dev/test)
      - Any Postgrex/DBConnection sandbox errors from test output
      - Credo complexity warnings on `__before_compile__` macros (this is a known false positive)

      ## Step 1: Pick 3–5 items worth filing

      From the health scan + opportunity scan, identify items that are:
      - NOT already in the open GitHub issues above
      - Specific and actionable (not vague refactoring suggestions)
      - Real problems in the actual codebase, not test environment artifacts

      Exclude: duplicates, style noise, speculative issues ("may not follow the same pattern").

      ## Step 2: File each one immediately

      For each item, call `create_github_issue` right away — do not output a list first.
      - title: specific, actionable
      - body: 3–5 sentences — what is wrong, which file/module, why it matters, what done looks like
      - labels: ["self-improvement"]

      ## If nothing is worth filing

      Output: "Nothing to file — all findings are already tracked or below threshold."
      Do not call create_github_issue.

      ## When done

      Output: "Filed N issues: [title1], [title2], ..."
      """,
      trigger: "manual",
      output_type: "freeform",
      dangerous_tool_mode: "intercept",
      max_tool_iterations: 15,
      loop_tools: ["create_github_issue"],
      context_providers: [
        %{
          "type" => "github_issues",
          "label" => "self-improvement",
          "header" => "## Currently Open Self-Improvement Issues"
        }
      ],
      roster: [%{"who" => "journeyman", "preferred_who" => "Backlog Manager", "how" => "solo", "when" => "sequential"}]
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

      Uses context providers to pre-inject data — no dice-roll tool calls for data retrieval.

      **Step 1: SI: Codebase Health Scan** (Code Auditor)
      - Context providers run `mix credo --all` and `mix test` BEFORE the model sees anything
      - Key source files (step_runner, quest_runner, ollama) are also pre-injected
      - Model has NO tools — just reads context and writes a findings report
      - Looks for: test gaps, error handling gaps, TODO comments, complexity
      - Outputs 3–8 findings in [Category] File:line format
      - Does NOT file issues — just reports

      **Step 2: SI: Feature & Opportunity Scan** (Product Analyst)
      - Context providers inject lore (project identity) and 4 key source files
      - Model has NO tools — analyzes injected content and writes opportunities
      - Different lens: product value, not code quality
      - Outputs 3–6 opportunities with effort estimates and file citations
      - Does NOT file issues — just reports

      **Step 3: SI: Backlog & Issue Filing** (Backlog Manager)
      - Context provider pre-fetches open GitHub issues labeled `self-improvement`
      - Synthesizes health scan + opportunity scan findings, deduplicates against open issues
      - Picks 3–5 high-value items not already tracked and files them directly via `create_github_issue`
      - No handoff — synthesis and filing happen in the same step
      - Issues labeled `self-improvement` get picked up by the SI Loop

      ## Self-Improvement Loop — source-triggered by GitHub issues labeled `self-improvement`

      1. SI: PM Triage — evaluates issue, writes implementation plan or rejects
      2. SI: Code Writer — implements in a worktree, opens a real GitHub PR
      3. SI: Code Reviewer — reviews correctness and patterns (verdict gate)
      4. SI: QA — runs tests, issues a verdict (verdict gate)
      5. SI: UX Designer — runs `mix excessibility`, checks accessibility
      6. SI: PM Merge Decision — squash-merges low-risk changes, cleans up worktree

      ## Key workflow rules

      - Scan steps have NO tools — all data is pre-injected by context providers
      - Only Backlog & Issue Filing calls tools (`create_github_issue`)
      - Code Writer MUST use setup_worktree and pass working_dir to every tool call
      - Code Writer opens a REAL GitHub PR with full description and Closes #N
      - UX Designer uses `mix excessibility` — not `mix test` or `mix format`
      - merge_pr auto-cleans up local worktrees after successful merge
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
        "Every 4 hours: codebase health scan → feature opportunity scan → backlog synthesis + issue filing in one step.",
      trigger: "scheduled",
      schedule: "0 */4 * * *",
      steps: step_entries,
      status: "active"
    })
  end
end
