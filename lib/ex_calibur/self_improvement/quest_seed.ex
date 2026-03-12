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
        "interval" => 300_000
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
        loop_mode: "reflect",
        max_iterations: 3,
        loop_tools: ["run_sandbox", "read_file"],
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
        description:
          "UX Designer reviews LiveView and UI changes for accessibility and usability, running mix excessibility as context.",
        trigger: "manual",
        output_type: "verdict",
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
      description:
        "Product Analyst proactively analyzes the codebase, runs credo, checks Obsidian/Lore if available, and files up to 5 GitHub issues labeled self-improvement.",
      trigger: "manual",
      output_type: "freeform",
      loop_mode: "reflect",
      max_iterations: 5,
      loop_tools: ["search_obsidian", "query_lore", "read_file", "list_files", "create_github_issue"],
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
