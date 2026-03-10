defmodule ExCalibur.QuestRunner do
  @moduledoc """
  Runs a Quest's ordered step definitions in sequence.

  Each step's output is formatted as a structured handoff block and prepended
  to the next step's input. The final step's result is returned.

  Steps are maps: %{"step_id" => "123", "order" => 1}
  Branch steps: %{"type" => "branch", "steps" => [...], "synthesizer" => "...", "order" => 1}
  """

  alias ExCalibur.Quests
  alias ExCalibur.StepRunner

  require Logger

  @doc "Run all steps of a quest, returning the final step result."
  def run(%{steps: steps} = quest, _input) when steps == [] do
    Logger.info("[QuestRunner] Quest #{quest.id} (#{quest.name}) has no steps")
    {:ok, %{steps: []}}
  end

  def run(quest, input) do
    ordered_steps = Enum.sort_by(quest.steps, &Map.get(&1, "order", 0))

    Logger.info("[QuestRunner] Running quest #{quest.id} (#{quest.name}), #{length(ordered_steps)} step(s)")

    # Zip each step with the next step for look-ahead (next step name for handoff)
    steps_with_next = Enum.zip(ordered_steps, tl(ordered_steps) ++ [nil])

    {results, _} =
      Enum.reduce(steps_with_next, {[], input}, fn {step, next_step}, {acc_results, current_input} ->
        case step["type"] do
          "branch" ->
            next_step_name =
              if next_step,
                do: resolve_step_name(next_step["step_id"] || next_step["synthesizer"])

            result = run_branch_step(step, current_input)

            synth_step_name =
              case resolve_step(step["synthesizer"]) do
                nil -> "Branch"
                s -> s.name
              end

            next_input =
              case result_to_text(result, "Branch: #{synth_step_name}", next_step_name) do
                "" -> current_input
                text -> "#{current_input}\n\n#{text}"
              end

            {acc_results ++ [result], next_input}

          _ ->
            step_id = step["step_id"] || step["quest_id"]
            next_step_name = if next_step, do: resolve_step_name(next_step["step_id"] || next_step["quest_id"])

            case resolve_step(step_id) do
              nil ->
                if is_nil(step_id),
                  do: Logger.warning("[QuestRunner] Quest has a step with nil step_id — remove it via the Quests UI"),
                  else: Logger.warning("[QuestRunner] Step #{step_id} not found, skipping")

                {acc_results ++ [{:error, :step_not_found}], current_input}

              resolved_step ->
                Logger.info("[QuestRunner] Running step #{resolved_step.id} (#{resolved_step.name})")
                result = StepRunner.run(resolved_step, current_input)

                next_input =
                  case result_to_text(result, resolved_step.name, next_step_name) do
                    "" -> current_input
                    text -> "#{current_input}\n\n#{text}"
                  end

                {acc_results ++ [result], next_input}
            end
        end
      end)

    case List.last(results) do
      {:ok, _} = ok -> ok
      _ -> {:ok, %{steps: results}}
    end
  end

  @doc "Format a StepRunner result as a structured handoff block for the next step."
  def result_to_text(result, current_step_name, next_step_name)

  def result_to_text({:ok, %{verdict: verdict, steps: steps}}, step_name, next_step_name) do
    member_lines =
      steps
      |> Enum.flat_map(& &1.results)
      |> Enum.map_join("\n", fn r ->
        "- **#{r.member}:** #{r.verdict} — #{String.slice(r[:reason] || "", 0, 120)}"
      end)

    question =
      if next_step_name,
        do: "\n**Open question for #{next_step_name}:** What does this verdict imply for your evaluation?",
        else: ""

    """
    ## Prior Step: #{step_name}
    **Verdict:** #{verdict}
    **Member findings:**
    #{member_lines}#{question}
    """
  end

  def result_to_text({:ok, %{artifact: %{title: title, body: body}}}, step_name, next_step_name) do
    question =
      if next_step_name,
        do: "\n**Open question for #{next_step_name}:** How does this artifact inform your evaluation?",
        else: ""

    """
    ## Prior Step: #{step_name}
    **Artifact:** #{title}
    #{body}#{question}
    """
  end

  def result_to_text({:ok, %{delivered: true, type: type}}, step_name, _next) do
    "## Prior Step: #{step_name}\nHerald delivered (#{type})\n"
  end

  def result_to_text(_, _, _), do: ""

  # Keep arity-1 version for backwards compatibility
  def result_to_text(result), do: result_to_text(result, "Previous Step", nil)

  @doc "Combine parallel branch results into a single context block for the synthesizer."
  def combine_branch_results(named_results, original_input) do
    branch_context =
      Enum.map_join(named_results, "\n\n", fn {name, result} ->
        result_to_text(result, name, nil)
      end)

    """
    #{original_input}

    ## Parallel Branch Results

    #{branch_context}
    """
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp run_branch_step(step, input) do
    step_ids = step["steps"] || step["quests"] || []
    synthesizer_id = step["synthesizer"]

    Logger.info("[QuestRunner] Running branch step: #{length(step_ids)} parallel step(s) + synthesizer")

    branch_results =
      step_ids
      |> Task.async_stream(
        fn step_id ->
          case resolve_step(step_id) do
            nil ->
              {step_id, {:error, :step_not_found}}

            resolved_step ->
              Logger.info("[QuestRunner] Branch: running #{resolved_step.name}")
              {resolved_step.name, StepRunner.run(resolved_step, input)}
          end
        end,
        timeout: 120_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, _} -> {"unknown", {:error, :timeout}}
      end)

    combined_input = combine_branch_results(branch_results, input)

    case resolve_step(synthesizer_id) do
      nil ->
        Logger.warning("[QuestRunner] Branch synthesizer #{synthesizer_id} not found")
        {:error, :synthesizer_not_found}

      synth ->
        Logger.info("[QuestRunner] Branch: running synthesizer #{synth.name}")
        StepRunner.run(synth, combined_input)
    end
  end

  defp resolve_step_name(step_id) when is_binary(step_id) do
    case resolve_step(step_id) do
      nil -> step_id
      step -> step.name
    end
  end

  defp resolve_step_name(_), do: nil

  defp resolve_step(step_id) when is_binary(step_id) do
    case Integer.parse(step_id) do
      {id, ""} -> Quests.get_step!(id)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp resolve_step(step_id) when is_integer(step_id) do
    Quests.get_step!(step_id)
  rescue
    _ -> nil
  end

  defp resolve_step(_), do: nil
end
