defmodule ExCortex.Ruminations.Runner do
  @moduledoc """
  Runs a Rumination's ordered step definitions in sequence.

  Each step's output is formatted as a structured handoff block and prepended
  to the next step's input. The final step's result is returned.

  Steps are maps: %{"step_id" => "123", "order" => 1}
  Branch steps: %{"type" => "branch", "steps" => [...], "synthesizer" => "...", "order" => 1}
  """

  alias ExCortex.Neuroplasticity.Loop
  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.ImpulseRunner
  alias ExCortex.Signals

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @doc "Check whether a gate step should halt the thought."
  def check_gate(%{"gate" => true}, {:ok, %{verdict: "fail"} = result}) do
    reason =
      result
      |> Map.get(:steps, [])
      |> Enum.flat_map(&Map.get(&1, :results, []))
      |> Enum.map_join("; ", &Map.get(&1, :reason, ""))

    {:gated, reason}
  end

  def check_gate(_, _), do: :continue

  @doc "Run all steps of a thought, returning the final step result."
  def run(%{steps: steps} = thought, _input) when steps == [] do
    Logger.info("[RuminationRunner] Thought #{thought.id} (#{thought.name}) has no steps")
    {:ok, %{steps: []}}
  end

  def run(thought, input, opts \\ []) do
    Tracer.with_span "thought.run", %{
      attributes: %{
        "thought.id" => thought.id,
        "thought.name" => thought.name,
        "thought.trigger" => thought.trigger || "manual",
        "thought.dry_run" => Keyword.get(opts, :dry_run, false)
      }
    } do
      do_run(thought, input, opts)
    end
  end

  defp do_run(thought, input, opts) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    ordered_steps = Enum.sort_by(thought.steps, &Map.get(&1, "order", 0))

    label = if dry_run?, do: "DRY RUN", else: "Running"
    Logger.info("[RuminationRunner] #{label} thought #{thought.id} (#{thought.name}), #{length(ordered_steps)} step(s)")

    # Create a daydream record
    initial_status = if dry_run?, do: "dry_run", else: "running"
    {:ok, daydream} = Ruminations.create_daydream(%{rumination_id: thought.id, status: initial_status})
    Phoenix.PubSub.broadcast(ExCortex.PubSub, "daydreams", {:daydream_started, daydream})

    # Zip each step with the next step for look-ahead (next step name for handoff)
    steps_with_next = Enum.zip(ordered_steps, tl(ordered_steps) ++ [nil])

    run_ctx = %{
      ordered_steps: ordered_steps,
      daydream: daydream,
      dry_run: dry_run?
    }

    {results, gated?} =
      try do
        {results, _} =
          Enum.reduce(steps_with_next, {[], input}, fn {step, next_step}, {acc_results, current_input} ->
            run_step_entry(step, next_step, current_input, acc_results, run_ctx)
          end)

        {results, false}
      catch
        {:gated, gated_results} -> {gated_results, true}
      end

    # Determine final status and record step results
    final_status =
      cond do
        dry_run? -> "dry_run"
        gated? -> "gated"
        match?({:ok, _}, List.last(results)) -> "complete"
        true -> "failed"
      end

    synapse_results =
      results
      |> Enum.with_index()
      |> Map.new(fn {result, idx} ->
        {to_string(idx), inspect_result(result)}
      end)

    {:ok, daydream} = Ruminations.update_daydream(daydream, %{status: final_status, synapse_results: synapse_results})
    Phoenix.PubSub.broadcast(ExCortex.PubSub, "daydreams", {:daydream_completed, daydream})

    if !Application.get_env(:ex_cortex, :sql_sandbox, false) do
      Task.Supervisor.start_child(ExCortex.AsyncTaskSupervisor, fn ->
        # Skip side effects (signals, artifacts) in dry run, but still extract memory
        if !dry_run?, do: post_artifacts(synapse_results, thought, daydream)

        ExCortex.Memory.Extractor.extract(%{
          id: daydream.id,
          rumination_name: thought.name,
          cluster_name: Map.get(thought, :cluster_name),
          dry_run: dry_run?,
          status: final_status,
          results: synapse_results,
          impulses: results |> Enum.with_index() |> Enum.map(fn {r, i} -> %{step: i, results: r} end)
        })
      end)
    end

    Tracer.set_attributes(%{"thought.status" => final_status, "thought.run_id" => daydream.id})

    case List.last(results) do
      {:ok, _} = ok -> ok
      _ -> {:ok, %{steps: results}}
    end
  end

  defp run_step_entry(%{"type" => "branch"} = step, next_step, current_input, acc_results, _ctx) do
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
  end

  defp run_step_entry(step, next_step, current_input, acc_results, ctx) do
    run_regular_step(step, next_step, current_input, acc_results, ctx)
  end

  defp run_regular_step(step, next_step, current_input, acc_results, ctx) do
    step_id = step["step_id"] || step["thought_id"]
    next_step_name = if next_step, do: resolve_step_name(next_step["step_id"] || next_step["thought_id"])

    case resolve_step(step_id) do
      nil ->
        log_missing_step(step_id)
        {acc_results ++ [{:error, :step_not_found}], current_input}

      resolved_step ->
        # In dry run mode, force all steps to dry_run dangerous_tool_mode
        resolved_step =
          if ctx.dry_run,
            do: Map.put(resolved_step, :dangerous_tool_mode, "dry_run"),
            else: resolved_step

        label = if ctx.dry_run, do: "[DRY RUN] ", else: ""
        Logger.info("[RuminationRunner] #{label}Running step #{resolved_step.id} (#{resolved_step.name})")
        t0 = System.monotonic_time(:millisecond)

        result =
          Tracer.with_span "thought.step", %{
            attributes: %{
              "step.id" => resolved_step.id,
              "step.name" => resolved_step.name,
              "step.output_type" => resolved_step.output_type || "verdict",
              "step.dry_run" => ctx.dry_run
            }
          } do
            r = ImpulseRunner.run(resolved_step, current_input)
            Tracer.set_attributes(%{"step.status" => inspect_result(r)["status"]})
            r
          end

        ms = System.monotonic_time(:millisecond) - t0

        Logger.info("[RuminationRunner] Step #{resolved_step.name} done in #{ms}ms: #{inspect_result(result)["status"]}")

        # Broadcast step completion for live UI updates
        Phoenix.PubSub.broadcast(ExCortex.PubSub, "daydreams", {:step_completed, %{
          daydream_id: ctx.daydream.id,
          step_index: length(acc_results),
          step_name: resolved_step.name,
          status: inspect_result(result)["status"],
          output_preview: inspect_result(result)["data"] |> to_string() |> String.slice(0, 200),
          duration_ms: ms,
          dry_run: ctx.dry_run
        }})

        # Async learning loop — runs retrospect without blocking the thought (skip in dry run)
        if !ctx.dry_run do
          step_run_data = %{id: ctx.daydream.id, results: inspect_result(result), input: current_input}

          Task.Supervisor.start_child(ExCortex.AsyncTaskSupervisor, fn ->
            Loop.retrospect(resolved_step, step_run_data)
          end)
        end

        handle_gate_result(step, result, resolved_step, current_input, acc_results, next_step_name, ctx.ordered_steps)
    end
  end

  defp log_missing_step(nil) do
    Logger.warning("[RuminationRunner] Rumination has a step with nil step_id — remove it via the Ruminations UI")
  end

  defp log_missing_step(step_id) do
    Logger.warning("[RuminationRunner] Step #{step_id} not found, skipping")
  end

  defp handle_gate_result(step, result, resolved_step, current_input, acc_results, next_step_name, ordered_steps) do
    case check_gate(step, result) do
      {:gated, reason} ->
        Logger.info("[RuminationRunner] GATED at #{resolved_step.name}: #{reason}")

        blocked_text =
          "## BLOCKED\n**Gated step:** #{resolved_step.name}\n**Verdict:** fail\n**Reason:** #{reason}\n\nThe thought was halted because this gate step returned a fail verdict."

        blocked_input = "#{current_input}\n\n#{blocked_text}"

        last_entry = List.last(ordered_steps)
        last_id = last_entry["step_id"] || last_entry["thought_id"]

        last_result =
          case resolve_step(last_id) do
            nil -> {:error, :step_not_found}
            ls -> ImpulseRunner.run(ls, blocked_input)
          end

        throw({:gated, acc_results ++ [result, last_result]})

      :continue ->
        next_input =
          case result_to_text(result, resolved_step.name, next_step_name) do
            "" -> current_input
            text -> "#{current_input}\n\n#{text}"
          end

        {acc_results ++ [result], next_input}
    end
  end

  @doc "Format a StepRunner result as a structured handoff block for the next step."
  def result_to_text(result, current_step_name, next_step_name)

  def result_to_text({:ok, %{verdict: verdict, steps: steps}}, step_name, next_step_name) do
    neuron_lines =
      steps
      |> Enum.flat_map(& &1.results)
      |> Enum.map_join("\n", fn r ->
        "- **#{r.neuron}:** #{r.verdict} — #{String.slice(r[:reason] || "", 0, 120)}"
      end)

    question =
      if next_step_name,
        do: "\n**Open question for #{next_step_name}:** What does this verdict imply for your evaluation?",
        else: ""

    """
    ## Prior Step: #{step_name}
    **Verdict:** #{verdict}
    **Neuron findings:**
    #{neuron_lines}#{question}
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
    "## Prior Step: #{step_name}\nExpression delivered (#{type})\n"
  end

  def result_to_text({:ok, %{signal: %{title: title, body: body}}}, step_name, next_step_name) do
    question =
      if next_step_name,
        do: "\n**Open question for #{next_step_name}:** How does this card inform your evaluation?",
        else: ""

    """
    ## Prior Step: #{step_name}
    **signal card:** #{title}
    #{String.slice(body || "", 0, 500)}#{question}
    """
  end

  def result_to_text({:ok, %{signals: _cards}}, step_name, _next) do
    "## Prior Step: #{step_name}\nMultiple signal cards posted.\n"
  end

  def result_to_text({:ok, %{output: output}}, step_name, _next_step_name) when is_binary(output) and output != "" do
    "## Prior Step: #{step_name}\n#{output}\n"
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
    step_ids = step["steps"] || step["thoughts"] || []
    synthesizer_id = step["synthesizer"]

    Logger.info("[RuminationRunner] Running branch step: #{length(step_ids)} parallel step(s) + synthesizer")

    branch_results =
      step_ids
      |> Task.async_stream(
        fn step_id ->
          case resolve_step(step_id) do
            nil ->
              {step_id, {:error, :step_not_found}}

            resolved_step ->
              Logger.info("[RuminationRunner] Branch: running #{resolved_step.name}")
              {resolved_step.name, ImpulseRunner.run(resolved_step, input)}
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
        Logger.warning("[RuminationRunner] Branch synthesizer #{synthesizer_id} not found")
        {:error, :synthesizer_not_found}

      synth ->
        Logger.info("[RuminationRunner] Branch: running synthesizer #{synth.name}")
        ImpulseRunner.run(synth, combined_input)
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
      {id, ""} -> Ruminations.get_synapse!(id)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp resolve_step(step_id) when is_integer(step_id) do
    Ruminations.get_synapse!(step_id)
  rescue
    _ -> nil
  end

  defp resolve_step(_), do: nil

  @artifact_tools ~w(create_github_issue open_pr merge_pr)

  defp post_artifacts(synapse_results, thought, daydream) do
    synapse_results
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

      case Signals.create_signal(%{
             type: "link",
             title: title,
             body: output,
             source: "thought:#{thought.name}",
             tags: ["self-improvement", type_tag],
             metadata: %{"url" => url, "daydream_id" => daydream.id},
             status: "active"
           }) do
        {:ok, _} -> Logger.info("[RuminationRunner] Posted artifact card: #{title}")
        {:error, e} -> Logger.warning("[RuminationRunner] Failed to post artifact card: #{inspect(e)}")
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
