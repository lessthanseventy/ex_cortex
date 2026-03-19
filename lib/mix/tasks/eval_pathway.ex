defmodule Mix.Tasks.EvalPathway do
  @moduledoc """
  Run golden-input evaluations against synapses and report pass rates.

  ## Usage

      mix eval_pathway                          # run all eval sets
      mix eval_pathway --synapse "Code Review"  # run evals for a specific synapse
      mix eval_pathway --tag security           # run evals tagged "security"

  ## Eval Sets

  Eval sets are stored as engrams with category "eval" and tagged with
  the synapse name (kebab-case). Each eval engram has:

  - title: "Eval: <synapse name> — <description>"
  - body: the test input
  - tags: ["eval", "synapse-name-kebab", optional domain tags]
  - metadata.expected_verdict: "pass" | "warn" | "fail"

  Create eval sets via:

      ExCortex.Memory.create_engram(%{
        title: "Eval: Code Review — clean code",
        body: "def hello, do: :world",
        tags: ["eval", "code-review"],
        category: "eval",
        importance: 3,
        source: "manual"
      })

  ## Output

  Reports per-synapse pass rates and overall accuracy.
  """

  use Mix.Task

  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.ImpulseRunner

  require Logger

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [synapse: :string, tag: :string])
    synapse_filter = opts[:synapse]
    tag_filter = opts[:tag]

    eval_engrams = load_eval_engrams(tag_filter)

    if eval_engrams == [] do
      Mix.shell().info(
        ~s(No eval engrams found. Create engrams with category: "eval" and tags: ["eval", "synapse-name"].)
      )

      System.halt(0)
    end

    # Group by synapse tag
    grouped = group_by_synapse(eval_engrams)

    grouped =
      if synapse_filter do
        target = synapse_filter |> String.downcase() |> String.replace(~r/\s+/, "-")
        Map.take(grouped, [target])
      else
        grouped
      end

    results =
      Enum.map(grouped, fn {synapse_tag, engrams} ->
        run_eval_set(synapse_tag, engrams)
      end)

    print_results(results)
  end

  defp load_eval_engrams(tag_filter) do
    import Ecto.Query

    query =
      from e in ExCortex.Memory.Engram,
        where: e.category == "eval" and "eval" in e.tags,
        order_by: [asc: e.title]

    query =
      if tag_filter do
        from e in query, where: ^tag_filter in e.tags
      else
        query
      end

    ExCortex.Repo.all(query)
  end

  defp group_by_synapse(engrams) do
    Enum.group_by(engrams, fn engram ->
      engram.tags
      |> Enum.reject(&(&1 == "eval"))
      |> List.first()
      |> Kernel.||("unknown")
    end)
  end

  defp run_eval_set(synapse_tag, engrams) do
    synapse_name = synapse_tag |> String.replace("-", " ") |> String.split() |> Enum.map_join(" ", &String.capitalize/1)

    synapse =
      Enum.find(Ruminations.list_synapses(), fn s -> String.downcase(s.name) == String.downcase(synapse_name) end)

    if synapse do
      Mix.shell().info("\nRunning #{length(engrams)} eval(s) for \"#{synapse.name}\"...")

      results =
        Enum.map(engrams, fn engram ->
          expected = engram.tags |> get_in([Access.filter(&String.starts_with?(&1, "expect:"))]) |> List.first()
          expected_verdict = if expected, do: String.replace(expected, "expect:", "")

          case ImpulseRunner.run(synapse, engram.body || "") do
            {:ok, %{verdict: actual}} ->
              match = expected_verdict == nil or actual == expected_verdict
              %{title: engram.title, expected: expected_verdict, actual: actual, match: match}

            {:error, reason} ->
              %{title: engram.title, expected: expected_verdict, actual: "error: #{inspect(reason)}", match: false}
          end
        end)

      pass_count = Enum.count(results, & &1.match)
      total = length(results)

      %{
        synapse: synapse.name,
        tag: synapse_tag,
        results: results,
        pass_count: pass_count,
        total: total,
        rate: if(total > 0, do: Float.round(pass_count / total * 100, 1), else: 0.0)
      }
    else
      Mix.shell().info("\nSkipping \"#{synapse_name}\" — synapse not found")
      %{synapse: synapse_name, tag: synapse_tag, results: [], pass_count: 0, total: 0, rate: 0.0}
    end
  end

  defp print_results(results) do
    Mix.shell().info("\n" <> String.duplicate("=", 60))
    Mix.shell().info("EVAL RESULTS")
    Mix.shell().info(String.duplicate("=", 60))

    Enum.each(results, fn r ->
      status = if r.rate >= 80, do: "PASS", else: "NEEDS WORK"
      Mix.shell().info("\n#{r.synapse}: #{r.rate}% (#{r.pass_count}/#{r.total}) — #{status}")

      Enum.each(r.results, fn result ->
        icon = if result.match, do: "  ✓", else: "  ✗"
        expected = if result.expected, do: " (expected: #{result.expected})", else: ""
        Mix.shell().info("#{icon} #{result.title} → #{result.actual}#{expected}")
      end)
    end)

    total_pass = Enum.sum(Enum.map(results, & &1.pass_count))
    total = Enum.sum(Enum.map(results, & &1.total))
    overall = if total > 0, do: Float.round(total_pass / total * 100, 1), else: 0.0

    Mix.shell().info("\n" <> String.duplicate("-", 60))
    Mix.shell().info("Overall: #{overall}% (#{total_pass}/#{total})")
    Mix.shell().info(String.duplicate("=", 60))
  end
end
