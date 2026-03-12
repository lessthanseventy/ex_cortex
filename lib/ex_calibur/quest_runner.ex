defmodule ExCalibur.QuestRunner do
  @moduledoc """
  Runs a Quest's ordered step definitions in sequence.

  Each step's output is formatted as a structured handoff block and prepended
  to the next step's input. The final step's result is returned.

  Steps are maps: %{"step_id" => "123", "order" => 1}
  Branch steps: %{"type" => "branch", "steps" => [...], "synthesizer" => "...", "order" => 1}
  """

  alias ExCalibur.LearningLoop
  alias ExCalibur.Lodge
  alias ExCalibur.Quests
  alias ExCalibur.StepRunner

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @doc "Run all steps of a quest, returning the final step result."
  def run(%{steps: steps} = quest, _input) when steps == [] do
    Logger.info("[QuestRunner] Quest #{quest.id} (#{quest.name}) has no steps")
    {:ok, %{steps: []}}
  end

  def run(quest, input) do
    Tracer.with_span "quest.run", %{
      attributes: %{
        "quest.id" => quest.id,
        "quest.name" => quest.name,
        "quest.trigger" => quest.trigger || "manual"
      }
    } do
      do_run(quest, input)
    end
  end

  defp do_run(quest, input) do
    ordered_steps = Enum.sort_by(quest.steps, &Map.get(&1, "order", 0))

    Logger.info("[QuestRunner] Running quest #{quest.id} (#{quest.name}), #{length(ordered_steps)} step(s)")

    # Create a quest run record
    {:ok, quest_run} = Quests.create_quest_run(%{quest_id: quest.id, status: "running"})
    Phoenix.PubSub.broadcast(ExCalibur.PubSub, "quest_runs", {:quest_run_started, quest_run})

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
                t0 = System.monotonic_time(:millisecond)

                result =
                  Tracer.with_span "quest.step", %{
                    attributes: %{
                      "step.id" => resolved_step.id,
                      "step.name" => resolved_step.name,
                      "step.output_type" => resolved_step.output_type || "verdict"
                    }
                  } do
                    r = StepRunner.run(resolved_step, current_input)
                    Tracer.set_attributes(%{"step.status" => inspect_result(r)["status"]})
                    r
                  end

                ms = System.monotonic_time(:millisecond) - t0

                Logger.info(
                  "[QuestRunner] Step #{resolved_step.name} done in #{ms}ms: #{inspect_result(result)["status"]}"
                )

                # Async learning loop — runs retrospect without blocking the quest
                step_run_data = %{id: quest_run.id, results: inspect_result(result), input: current_input}

                Task.Supervisor.start_child(ExCalibur.AsyncTaskSupervisor, fn ->
                  LearningLoop.retrospect(resolved_step, step_run_data)
                end)

                next_input =
                  case result_to_text(result, resolved_step.name, next_step_name) do
                    "" -> current_input
                    text -> "#{current_input}\n\n#{text}"
                  end

                {acc_results ++ [result], next_input}
            end
        end
      end)

    # Determine final status and record step results
    final_status = if match?({:ok, _}, List.last(results)), do: "complete", else: "failed"

    step_results =
      results
      |> Enum.with_index()
      |> Map.new(fn {result, idx} ->
        {to_string(idx), inspect_result(result)}
      end)

    {:ok, quest_run} = Quests.update_quest_run(quest_run, %{status: final_status, step_results: step_results})
    Phoenix.PubSub.broadcast(ExCalibur.PubSub, "quest_runs", {:quest_run_completed, quest_run})

    Task.Supervisor.start_child(ExCalibur.AsyncTaskSupervisor, fn ->
      post_artifacts(step_results, quest, quest_run)
    end)

    Tracer.set_attributes(%{"quest.status" => final_status, "quest.run_id" => quest_run.id})

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

  def result_to_text({:ok, %{lodge_card: %{title: title, body: body}}}, step_name, next_step_name) do
    question =
      if next_step_name,
        do: "\n**Open question for #{next_step_name}:** How does this card inform your evaluation?",
        else: ""

    """
    ## Prior Step: #{step_name}
    **Lodge Card:** #{title}
    #{String.slice(body || "", 0, 500)}#{question}
    """
  end

  def result_to_text({:ok, %{lodge_cards: _cards}}, step_name, _next) do
    "## Prior Step: #{step_name}\nMultiple lodge cards posted.\n"
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

  @artifact_tools ~w(create_github_issue open_pr merge_pr)

  defp post_artifacts(step_results, quest, quest_run) do
    step_results
    |> Map.values()
    |> Enum.flat_map(&Map.get(&1, "tool_calls", []))
    |> Enum.filter(&(&1["tool"] in @artifact_tools))
    |> Enum.flat_map(fn call ->
      output = call["output"] || ""

      output
      |> then(&Regex.scan(~r{https://github\.com/\S+}, &1))
      |> List.flatten()
      |> Enum.map(&{call["tool"], &1, output})
    end)
    |> Enum.uniq_by(fn {_tool, url, _} -> url end)
    |> Enum.each(fn {tool, url, output} ->
      {type_tag, title} = artifact_card_info(tool, url, output)

      case Lodge.create_card(%{
             type: "link",
             title: title,
             body: output,
             source: "quest:#{quest.name}",
             tags: ["self-improvement", type_tag],
             metadata: %{"url" => url, "quest_run_id" => quest_run.id},
             status: "active"
           }) do
        {:ok, _} -> Logger.info("[QuestRunner] Posted artifact card: #{title}")
        {:error, e} -> Logger.warning("[QuestRunner] Failed to post artifact card: #{inspect(e)}")
      end
    end)
  end

  defp artifact_card_info("create_github_issue", url, _output) do
    num = url |> String.split("/") |> List.last()
    {"issue", "Issue ##{num}"}
  end

  defp artifact_card_info("open_pr", url, _output) do
    num = url |> String.split("/") |> List.last()
    {"pr", "PR ##{num}"}
  end

  defp artifact_card_info("merge_pr", url, output) do
    num = url |> String.split("/") |> List.last()

    title =
      case Regex.run(~r{PR #\d+ merged}, output) do
        [match] -> match
        _ -> "PR ##{num} merged"
      end

    {"merged", title}
  end

  defp artifact_card_info(tool, url, _output) do
    num = url |> String.split("/") |> List.last()
    {tool, "Artifact ##{num}"}
  end

  defp inspect_result({:ok, result}) when is_map(result) do
    tool_calls = extract_tool_calls(result)
    base = %{"status" => "ok", "data" => inspect(Map.delete(result, :tool_calls))}
    if tool_calls == [], do: base, else: Map.put(base, "tool_calls", tool_calls)
  end

  defp inspect_result({:error, reason}), do: %{"status" => "error", "reason" => inspect(reason)}
  defp inspect_result(other), do: %{"status" => "unknown", "data" => inspect(other)}

  defp extract_tool_calls(%{tool_calls: calls}) when is_list(calls), do: calls

  defp extract_tool_calls(%{steps: steps}) when is_list(steps) do
    steps
    |> Enum.flat_map(fn step -> Map.get(step, :results, []) end)
    |> Enum.flat_map(fn r -> Map.get(r, :tool_calls, []) end)
  end

  defp extract_tool_calls(_), do: []
end
