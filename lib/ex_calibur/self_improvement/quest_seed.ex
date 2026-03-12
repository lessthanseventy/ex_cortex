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

  @lore_title "José Valim's Grimoire: Elixir Testing Patterns"

  defp seed_lore do
    existing =
      ExCalibur.Repo.exists?(
        from(e in ExCalibur.Lore.LoreEntry, where: e.title == @lore_title)
      )

    unless existing do
      ExCalibur.Lore.create_entry(%{
        title: @lore_title,
        source: "manual",
        importance: 5,
        tags: ["elixir", "testing", "patterns", "grimoire"],
        body: """
        # José Valim's Grimoire: Elixir Testing Patterns

        *Authoritative guidance on modern Elixir testing for this codebase.*

        ---

        ## Never mock module functions by assignment

        This is invalid Elixir — modules are compiled bytecode, not mutable objects:

        ```elixir
        # WRONG — will not compile
        MyModule.some_function = fn _ -> :ok end
        ```

        For DB-dependent code, use real data. For external services, inject the dependency
        or define a behaviour and use `Mox`. When in doubt, test with the real thing.

        ---

        ## Use DataCase for anything that touches the database

        ```elixir
        # Pure unit test — no DB needed
        defmodule MyTest do
          use ExUnit.Case, async: true
          ...
        end

        # DB-dependent test — use DataCase (wraps each test in a rolled-back transaction)
        defmodule MyRepoTest do
          use ExCalibur.DataCase, async: true
          ...
        end
        ```

        `async: true` is safe on DataCase because each test gets its own sandbox connection.
        Use `async: false` only when tests share global state (PubSub subscriptions, named processes).

        ---

        ## Non-empty list checks

        `length/1` traverses the entire list — O(n) — before you can check the result.
        Prefer pattern matching or direct comparison:

        ```elixir
        # SLOW — avoid
        assert length(list) > 0

        # FAST — prefer
        assert list != []

        # Even better when you need the first element too
        assert [_ | _] = list
        ```

        ---

        ## Assert on structure, not just truthiness

        ```elixir
        # Weak
        assert result

        # Better — asserts shape and binds the value
        assert {:ok, %{id: id}} = result
        ```

        ---

        ## Async messages: assert_receive, not sleep

        ```elixir
        # BAD
        Process.sleep(100)
        assert something_happened()

        # GOOD
        assert_receive {:event, :my_event}, 500
        ```

        ---

        ## Test the public interface, not private functions

        Private functions are implementation details. Test them indirectly through the
        public API. If a private function is complex enough to test directly, it should
        probably be a separate module.

        ---

        ## ExUnit tags for selective running

        ```elixir
        @tag :integration
        test "hits the real API" do ...

        # Run only integration tests
        # mix test --only integration

        # Skip slow tests
        # mix test --exclude slow
        ```
        """
      })
    end
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
