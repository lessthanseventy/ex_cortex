defmodule ExCalibur.SelfImprovement.QuestSeed do
  @moduledoc "Seeds the self-improvement pipeline — called when Dev Team charter is installed."

  import Ecto.Query

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
    "SI: Product Analyst Sweep"
  ]

  @si_quest_names ["Self-Improvement Loop", "SI: Analyst Sweep"]

  def seed(opts \\ %{}) do
    repo = Map.get(opts, :repo, "")
    cleanup()

    with {:ok, source} <- create_source(repo),
         {:ok, steps} <- create_steps(),
         {:ok, quest} <- create_quest(source, steps),
         {:ok, sweep_step} <- create_sweep_step(),
         {:ok, sweep_quest} <- create_sweep_quest(sweep_step) do
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
        description:
          "Project Manager evaluates a self-improvement GitHub issue, writes an implementation plan, and decides whether to proceed or reject.",
        trigger: "manual",
        output_type: "freeform",
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
        description:
          "Code Writer implements the issue in a git worktree — reads relevant files, writes the implementation, runs tests, and opens a PR.",
        trigger: "manual",
        output_type: "freeform",
        roster: [
          %{
            "who" => "all",
            "preferred_who" => "Code Writer",
            "how" => "solo",
            "when" => "sequential"
          }
        ]
      },
      %{
        name: "SI: Code Reviewer",
        description:
          "Code Reviewer checks the PR for correctness, security, and pattern adherence. Comments findings and approves or requests changes.",
        trigger: "manual",
        output_type: "verdict",
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
        description:
          "QA / Test Writer runs the test suite and credo, writes missing tests, and issues a verdict that gates merge.",
        trigger: "manual",
        output_type: "verdict",
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
    step_entries =
      steps
      |> Enum.with_index(1)
      |> Enum.map(fn {step, order} -> %{"step_id" => step.id, "order" => order} end)

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

  defp create_sweep_step do
    Quests.create_step(%{
      name: "SI: Product Analyst Sweep",
      description: """
      Product Analyst proactively analyzes the codebase, runs credo, checks Obsidian/Lore if available, and files up to 5 GitHub issues labeled self-improvement.

      If you write or modify any files (tests, source code, config), you MUST run `mix test` via run_sandbox afterward.
      If the sandbox returns a compile error or test failure, fix the issue immediately — read the failing file, diagnose the error, correct it, and re-run.
      Do NOT file a GitHub issue for a problem you introduced. Only file issues for pre-existing problems you cannot fix in this session.

      Query lore before writing Elixir tests — the grimoire contains important testing patterns for this codebase.
      """,
      trigger: "manual",
      output_type: "freeform",
      loop_mode: "reflect",
      max_iterations: 3,
      loop_tools: ["run_sandbox", "read_file", "write_file", "edit_file", "list_files", "query_lore"],
      roster: [
        %{
          "who" => "all",
          "preferred_who" => "Product Analyst",
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

      ## SI Quest Pipeline (simpler, seeded by quest_seed.ex)

      **SI: Analyst Sweep** — scheduled every 4 hours
      - Reads codebase, runs credo, checks lore, files up to 5 GitHub issues
      - Has reflect loop with write/edit tools so it can fix what it breaks
      - Rule: fix problems you can fix directly; file issues only for what you can't

      **Self-Improvement Loop** — source-triggered by GitHub issues labeled `self-improvement`
      1. SI: PM Triage — evaluates issue, writes implementation plan
      2. SI: Code Writer — implements in a worktree
      3. SI: Code Reviewer — reviews correctness and patterns
      4. SI: QA — runs tests, writes missing tests, issues a verdict
      5. SI: UX Designer — runs `mix excessibility`, checks accessibility
      6. SI: PM Merge Decision — auto-merge or escalate to CTO

      ## Dev Team Charter (advanced, manual)

      Quests: Triage Issues · Implement Issue · Review PR · QA Check · UX Review · Merge Decision
      Campaign: Self-Improvement Loop chains them together.

      ## Key workflow rules

      - Analyst sweep: query lore before writing tests or code
      - If a sandbox run fails after you wrote code, fix it before finishing
      - Do not file issues for problems you introduced and couldn't fix
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
      importance: 3,
      body: """
      # ExCalibur: Credo Baseline

      `mix credo` currently reports ~40 refactoring opportunities and ~10 warnings.
      These are pre-existing. Do not file issues for them unless you have a concrete fix.

      ## Accepted complexity (known, do not file issues)

      - `ExCaliburWeb.GuildHallLive.handle_event/3` — cyclomatic complexity 15
      - `ExCalibur.LLM.Claude.run_agent_loop/5` — nesting depth 3
      - `ExCaliburWeb.SettingsLive.handle_event/3` — nesting depth 3
      - `ExCaliburWeb.QuestsLive.handle_event/3` — nesting depth 3
      - `ExCaliburWeb.LodgeLive.handle_event/3` — nesting depth 3
      - ~35 more refactoring opportunities across the codebase

      ## Worth filing issues for

      - New credo issues introduced by recent changes
      - `length/1` checks easily replaced with `!= []`
      - Issues in files you're already touching for another reason

      ## Worth ignoring

      - The ~40 pre-existing refactoring opportunities
      - Complexity in large LiveViews (structural changes, high risk)
      """
    }
  ]

  defp seed_lore do
    existing_titles =
      Repo.all(
        from(e in ExCalibur.Lore.LoreEntry,
          where: e.title in ^Enum.map(@lore_entries, & &1.title),
          select: e.title
        )
      )

    @lore_entries
    |> Enum.reject(&(&1.title in existing_titles))
    |> Enum.each(&ExCalibur.Lore.create_entry(Map.put(&1, :source, "manual")))
  end

  defp create_sweep_quest(sweep_step) do
    Quests.create_quest(%{
      name: "SI: Analyst Sweep",
      description:
        "Product Analyst proactively analyzes the codebase every 4 hours — reading code, running credo, checking Obsidian/Lore if available, and filing GitHub issues.",
      trigger: "scheduled",
      schedule: "0 */4 * * *",
      steps: [%{"step_id" => sweep_step.id, "order" => 1}],
      status: "active"
    })
  end
end
