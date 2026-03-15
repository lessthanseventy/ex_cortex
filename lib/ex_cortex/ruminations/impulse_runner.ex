defmodule ExCortex.Ruminations.ImpulseRunner do
  @moduledoc """
  Runs a Step's roster against input text, returning a trace of verdicts.

  ## Roster step format
    %{
      "who"         => "all" | "apprentice" | "journeyman" | "master" | "team:X" | neuron_id | "claude_haiku" | "claude_sonnet" | "claude_opus",
      "when"        => "parallel" | "sequential",
      "how"         => "consensus" | "solo" | "majority",
      "escalate_on" => "never" | "always" | %{"type" => "verdict", "values" => [...]} | %{"type" => "confidence", "threshold" => float}
    }

  ## Return value
    {:ok, %{verdict: "pass"|"warn"|"fail", steps: [step_trace, ...]}}
    {:error, reason}
  """

  import Ecto.Query

  alias ExCortex.ContextProviders.ContextProvider
  alias ExCortex.Neurons.Neuron
  alias ExCortex.Repo

  require Logger

  @verdict_order %{"fail" => 0, "warn" => 1, "abstain" => 2, "pass" => 3}
  @rank_order %{"apprentice" => 0, "journeyman" => 1, "master" => 2}

  @expression_types ~w(slack webhook github_issue github_pr email pagerduty)

  @dangerous_tools ~w(send_email create_github_issue comment_github run_rumination merge_pr git_pull restart_app close_issue nextcloud_talk)
  @write_tool_names ~w(write_file edit_file git_commit create_obsidian_note daily_obsidian)

  def dangerous?(tool_name), do: tool_name in @dangerous_tools

  @doc "Returns true if the given tool list contains any write tools that modify files."
  def has_write_tools?(loop_tools) when is_list(loop_tools) do
    Enum.any?(loop_tools, &(&1 in @write_tool_names))
  end

  def has_write_tools?(_), do: false

  def intercept_dangerous_tool(tool_name, tool_args, rumination_id, context \\ nil) do
    {description, suggestion} = proposal_content(tool_name, tool_args, context)

    ExCortex.Ruminations.create_proposal(%{
      synapse_id: rumination_id,
      type: "tool_action",
      description: description,
      details: %{"suggestion" => suggestion},
      status: "pending",
      tool_name: tool_name,
      tool_args: tool_args,
      context: context
    })
  end

  defp proposal_content("create_github_issue", %{"title" => title, "body" => body}, _context) do
    {title, body}
  end

  defp proposal_content("create_github_issue", %{"title" => title}, _context) do
    {title, "No description provided."}
  end

  defp proposal_content(tool_name, _args, context) do
    {"Tool call: #{tool_name}", context || "Automated tool call"}
  end

  @doc "Build the ordered list of models to try: assigned model first, then fallback chain (deduped)."
  defdelegate fallback_models_for(model, chain), to: ExCortex.LLM.Ollama

  @doc """
  Run a step roster against `input_text`.
  Accepts either a `Step` struct or just a bare roster list.
  Returns `{:ok, result}` or `{:error, reason}`.
  """

  # Reflect mode — run neurons, if unsatisfied gather context via tools and retry
  def run(%{loop_mode: "reflect"} = thought, input_text) do
    context = ContextProvider.assemble(thought.context_providers || [], thought, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    threshold = thought.reflect_threshold || 0.6
    reflect_on = thought.reflect_on_verdict || []
    max_iter = thought.max_iterations || 3
    tools = ExCortex.Tools.Registry.resolve_tools(thought.loop_tools || [])

    do_reflect(thought, augmented, tools, threshold, reflect_on, max_iter, 0)
  end

  # Escalate mode — try ranks in order until result is satisfying
  def run(%{escalate: true} = thought, input_text) do
    context = ContextProvider.assemble(thought.context_providers || [], thought, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    threshold = thought.escalate_threshold || 0.6
    escalate_on = thought.escalate_on_verdict || []

    ["apprentice", "journeyman", "master"]
    |> Enum.reduce_while(nil, fn rank, _acc ->
      try_escalate_rank(rank, thought, augmented, threshold, escalate_on)
    end)
    |> then(fn
      nil -> {:ok, %{verdict: "abstain", steps: []}}
      result -> result
    end)
  end

  def run(%{min_rank: min_rank} = thought, input_text) when is_binary(min_rank) and min_rank != "" do
    min_order = Map.get(@rank_order, min_rank, 0)

    eligible_ranks =
      @rank_order
      |> Enum.filter(fn {_rank, order} -> order >= min_order end)
      |> Enum.map(fn {rank, _} -> rank end)

    has_eligible =
      Repo.exists?(
        from m in Neuron,
          where:
            m.type == "role" and m.status == "active" and
              fragment("config->>'rank' = ANY(?)", ^eligible_ranks)
      )

    if has_eligible do
      context = ContextProvider.assemble(thought.context_providers || [], thought, input_text)
      augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"
      run(thought.roster, augmented, dangerous_tool_opts(thought))
    else
      {:error, {:rank_insufficient, "Step requires #{min_rank} or higher — no eligible neurons found"}}
    end
  end

  def run(%{output_type: type} = thought, input_text) when type in @expression_types do
    context = ContextProvider.assemble(thought.context_providers || [], thought, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    with {:ok, expression} <- ExCortex.Expressions.get_by_name(thought.expression_name || ""),
         {:ok, attrs} <- run_artifact(thought, augmented),
         :ok <- ExCortex.Expressions.deliver(expression, thought, attrs) do
      {:ok, %{delivered: true, type: type, title: attrs.title}}
    end
  end

  def run(%{output_type: "artifact"} = thought, input_text) do
    context = ContextProvider.assemble(thought.context_providers || [], thought, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"
    result = run_artifact(thought, augmented)

    case result do
      {:ok, attrs} ->
        forced_tags = thought.engram_tags || []
        attrs = Map.update(attrs, :tags, forced_tags, &Enum.uniq(&1 ++ forced_tags))
        ExCortex.Memory.write_artifact(thought, attrs)
        {:ok, %{artifact: attrs}}

      error ->
        error
    end
  end

  def run(%{output_type: "freeform"} = thought, input_text) do
    context = ContextProvider.assemble(thought.context_providers || [], thought, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    roster = thought.roster || []

    case roster do
      [] -> {:error, :no_roster}
      [step | _] -> run_freeform_step(step, augmented, thought)
    end
  end

  def run(%{output_type: "signal"} = thought, input_text) do
    context = ContextProvider.assemble(thought.context_providers || [], thought, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    case run_artifact(thought, augmented) do
      {:ok, attrs} -> post_signal_cards(thought, attrs)
      error -> error
    end
  end

  def run(thought, input_text) when is_struct(thought) do
    context = ContextProvider.assemble(thought.context_providers || [], thought, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"
    run(thought.roster, augmented, dangerous_tool_opts(thought))
  end

  def run(roster, input_text, opts) when is_list(roster) do
    {steps, final_verdict} =
      Enum.reduce_while(roster, {[], nil}, fn step, {traces, _prev_verdict} ->
        neurons = resolve_neurons(step)

        synapse_results = run_step(neurons, step["how"], input_text, opts)

        step_verdict = aggregate(synapse_results, step["how"])

        trace = %{
          who: step["who"],
          how: step["how"],
          results: synapse_results,
          verdict: step_verdict
        }

        if should_escalate?(step["escalate_on"], step_verdict) do
          {:halt, {traces ++ [trace], step_verdict}}
        else
          {:cont, {traces ++ [trace], step_verdict}}
        end
      end)

    result = {:ok, %{verdict: final_verdict || "pass", steps: steps}}
    ExCortex.TrustScorer.record_run(steps)
    result
  end

  # ---------------------------------------------------------------------------
  # Neuron resolution
  # ---------------------------------------------------------------------------

  @rank_values ["apprentice", "journeyman", "master"]

  # When preferred_who is combined with a rank-based "who", filter by both name AND rank.
  # This ensures "who: journeyman, preferred_who: Product Analyst" returns only the
  # journeyman-ranked Product Analyst, not all perspectives of that role.
  defp resolve_neurons(%{"preferred_who" => name, "who" => rank} = step)
       when is_binary(name) and name != "" and rank in @rank_values do
    case from(m in Neuron,
           where:
             m.type == "role" and m.status == "active" and m.name == ^name and
               fragment("config->>'rank' = ?", ^rank)
         )
         |> Repo.all()
         |> Enum.map(&neuron_to_runner_spec/1) do
      [] -> resolve_neurons(%{step | "preferred_who" => nil})
      neurons -> neurons
    end
  end

  defp resolve_neurons(%{"preferred_who" => name} = step) when is_binary(name) and name != "" do
    case from(m in Neuron,
           where: m.type == "role" and m.status == "active" and m.name == ^name
         )
         |> Repo.all()
         |> Enum.map(&neuron_to_runner_spec/1) do
      [] -> resolve_neurons(%{step | "preferred_who" => nil})
      neurons -> neurons
    end
  end

  defp resolve_neurons(%{"who" => who}), do: resolve_neurons(who)
  defp resolve_neurons(step) when is_map(step), do: resolve_neurons(Map.get(step, "who", "all"))

  defp resolve_neurons("all") do
    from(m in Neuron, where: m.type == "role" and m.status == "active")
    |> Repo.all()
    |> Enum.map(&neuron_to_runner_spec/1)
  end

  defp resolve_neurons("apprentice"), do: resolve_by_rank("apprentice")

  defp resolve_neurons("journeyman"), do: resolve_by_rank("journeyman")

  defp resolve_neurons("master"), do: resolve_by_rank("master")

  defp resolve_neurons("challenger") do
    case ExCortex.Neurons.Builtin.get("challenger") do
      nil ->
        []

      neuron ->
        rank_config = neuron.ranks[:journeyman]

        [
          %{
            provider: "ollama",
            model: rank_config.model,
            system_prompt: neuron.system_prompt,
            name: neuron.name,
            tools: []
          }
        ]
    end
  end

  defp resolve_neurons("team:" <> team) do
    from(m in Neuron,
      where: m.type == "role" and m.status == "active" and m.team == ^team
    )
    |> Repo.all()
    |> Enum.map(&neuron_to_runner_spec/1)
  end

  defp resolve_neurons(claude_tier) when claude_tier in ["claude_haiku", "claude_sonnet", "claude_opus"] do
    [%{provider: "claude", model: claude_tier, name: claude_tier, system_prompt: nil, tools: []}]
  end

  defp resolve_neurons(neuron_id) when is_binary(neuron_id) do
    case Repo.get(Neuron, neuron_id) do
      nil -> []
      m -> [neuron_to_runner_spec(m)]
    end
  end

  defp resolve_by_rank(rank) do
    from(m in Neuron,
      where:
        m.type == "role" and m.status == "active" and
          fragment("config->>'rank' = ?", ^rank)
    )
    |> Repo.all()
    |> Enum.map(&neuron_to_runner_spec/1)
  end

  defp neuron_to_runner_spec(db) do
    %{
      provider: db.config["provider"] || "ollama",
      model: db.config["model"] || "phi4-mini",
      system_prompt: db.config["system_prompt"] || "",
      name: db.name,
      tools: resolve_member_tools(db.config["tools"])
    }
  end

  defp resolve_member_tools(nil), do: []
  defp resolve_member_tools("all_safe"), do: ExCortex.Tools.Registry.resolve_tools(:all_safe)
  defp resolve_member_tools("write"), do: ExCortex.Tools.Registry.resolve_tools(:write)
  defp resolve_member_tools("dangerous"), do: ExCortex.Tools.Registry.resolve_tools(:dangerous)
  defp resolve_member_tools("yolo"), do: ExCortex.Tools.Registry.resolve_tools(:dangerous)
  defp resolve_member_tools(names) when is_list(names), do: ExCortex.Tools.Registry.resolve_tools(names)
  defp resolve_member_tools(_), do: []

  # ---------------------------------------------------------------------------
  # Running a step
  # ---------------------------------------------------------------------------

  defp run_step(neurons, _how, input_text, opts) do
    Enum.map(neurons, fn neuron ->
      require Logger

      result = call_member(neuron, input_text, opts)
      r = Map.put(result, :neuron, neuron.name)

      Logger.info(
        "[StepRunner] #{neuron.name} (#{neuron.provider}/#{neuron.model}): verdict=#{r.verdict} confidence=#{r.confidence} tool_calls=#{length(r[:tool_calls] || [])}"
      )

      r
    end)
  end

  defp effective_tools(member_tools, opts) do
    case Keyword.get(opts, :override_tools) do
      :none -> []
      names when is_list(names) and names != [] -> resolve_member_tools(names)
      _ -> member_tools
    end
  end

  defp call_member(
         %{provider: provider, model: model, system_prompt: system_prompt, tools: member_tools},
         input_text,
         opts
       ) do
    tools = effective_tools(member_tools, opts)
    base = system_prompt || default_claude_prompt()
    prompt = ensure_verdict_format(base, tools)

    result =
      if tools == [] do
        ExCortex.LLM.complete(provider, model, prompt, input_text)
      else
        ExCortex.LLM.complete_with_tools(provider, model, prompt, input_text, tools, opts)
      end

    case result do
      {:ok, text, tool_log} ->
        require Logger

        Logger.debug("[StepRunner] raw response (#{byte_size(text)}B): #{String.slice(text, 0, 300)}")
        text |> parse_verdict() |> Map.put(:tool_calls, tool_log)

      {:ok, text} ->
        require Logger

        Logger.debug("[StepRunner] raw response (#{byte_size(text)}B): #{String.slice(text, 0, 300)}")
        text |> parse_verdict() |> Map.put(:tool_calls, [])

      {:error, _, _} ->
        %{verdict: "abstain", confidence: 0.0, reason: "LLM error (#{provider})", tool_calls: []}

      {:error, _} ->
        %{verdict: "abstain", confidence: 0.0, reason: "LLM error (#{provider})", tool_calls: []}
    end
  end

  defp ensure_verdict_format(prompt, tools) do
    verdict_suffix =
      if tools == [] do
        "\n\nRespond with:\nACTION: pass | warn | fail | abstain\nCONFIDENCE: 0.0-1.0\nREASON: your reasoning"
      else
        "\n\nYou have access to tools — use them to gather information before giving your verdict.\n\nRespond with:\nACTION: pass | warn | fail | abstain\nCONFIDENCE: 0.0-1.0\nREASON: your reasoning"
      end

    if String.contains?(prompt, "ACTION:") do
      prompt
    else
      prompt <> verdict_suffix
    end
  end

  # Like call_member but returns raw text — used for freeform thoughts.
  # Returns {text, tool_log} tuple or nil on failure.
  defp call_member_raw(
         %{provider: provider, model: model, system_prompt: system_prompt, tools: member_tools},
         input_text,
         opts
       ) do
    tools = effective_tools(member_tools, opts)
    prompt = system_prompt || ""

    result =
      if tools == [] do
        ExCortex.LLM.complete(provider, model, prompt, input_text)
      else
        ExCortex.LLM.complete_with_tools(provider, model, prompt, input_text, tools, opts)
      end

    case result do
      {:ok, text, tool_log} -> {text, tool_log}
      {:ok, text} -> {text, []}
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Verdict parsing
  # ---------------------------------------------------------------------------

  defp parse_verdict(text) do
    verdict =
      case Regex.run(~r/ACTION:\s*(pass|warn|fail|abstain)/i, text) do
        [_, v] -> String.downcase(v)
        _ -> "abstain"
      end

    confidence =
      case Regex.run(~r/CONFIDENCE:\s*([0-9.]+)/i, text) do
        [_, c] -> String.to_float(c)
        _ -> 0.5
      end

    reason =
      case Regex.run(~r/REASON:\s*(.+)/is, text) do
        [_, r] -> String.trim(r)
        _ -> ""
      end

    %{verdict: verdict, confidence: confidence, reason: reason}
  end

  # ---------------------------------------------------------------------------
  # Aggregation
  # ---------------------------------------------------------------------------

  defp aggregate([], _), do: "abstain"

  defp aggregate(results, "solo") do
    results |> List.first() |> Map.get(:verdict, "abstain")
  end

  defp aggregate(results, "consensus") do
    verdicts = Enum.map(results, & &1.verdict)
    if Enum.uniq(verdicts) == [hd(verdicts)], do: hd(verdicts), else: worst_verdict(verdicts)
  end

  defp aggregate(results, _majority) do
    verdicts = Enum.map(results, & &1.verdict)
    verdicts |> Enum.frequencies() |> Enum.max_by(fn {_, count} -> count end) |> elem(0)
  end

  defp worst_verdict(verdicts) do
    Enum.min_by(verdicts, &Map.get(@verdict_order, &1, 2))
  end

  # ---------------------------------------------------------------------------
  # Escalation
  # ---------------------------------------------------------------------------

  defp should_escalate?("always", _verdict), do: true
  defp should_escalate?("never", _verdict), do: false

  defp should_escalate?(%{"type" => "verdict", "values" => values}, verdict) do
    verdict in values
  end

  defp should_escalate?(%{"type" => "confidence", "threshold" => _threshold}, _verdict) do
    # Per-result confidence gating is handled by the caller; step-level always passes
    false
  end

  defp should_escalate?(_, _), do: false

  # ---------------------------------------------------------------------------
  # Reflect mode helpers
  # ---------------------------------------------------------------------------

  defp do_reflect(thought, input_text, _tools, _threshold, _reflect_on, max_iter, iter) when iter >= max_iter do
    run(thought.roster, input_text, dangerous_tool_opts(thought))
  end

  defp do_reflect(thought, input_text, tools, threshold, reflect_on, max_iter, iter) do
    result = run(thought.roster, input_text, dangerous_tool_opts(thought))

    case result do
      {:ok, %{verdict: v, steps: steps}} = ok ->
        avg_confidence =
          steps
          |> Enum.flat_map(& &1.results)
          |> Enum.map(&Map.get(&1, :confidence, 0.5))
          |> then(fn
            [] -> 0.5
            cs -> Enum.sum(cs) / length(cs)
          end)

        satisfied = avg_confidence >= threshold and v not in reflect_on

        if satisfied or tools == [] do
          ok
        else
          extra_context = gather_reflect_context(tools, v)
          augmented = "#{input_text}\n\n## Reflection Context\n#{extra_context}"
          do_reflect(thought, augmented, tools, threshold, reflect_on, max_iter, iter + 1)
        end

      other ->
        other
    end
  end

  defp gather_reflect_context(tools, verdict) do
    memory_tool = Enum.find(tools, &(&1.name == "query_memory"))

    if memory_tool do
      gather_memory_context(memory_tool, verdict)
    else
      gather_tool_context(tools)
    end
  end

  defp gather_memory_context(memory_tool, verdict) do
    case ReqLLM.Tool.execute(memory_tool, %{"tags" => [], "limit" => 3}) do
      {:ok, content} -> "Prior memory context (verdict was #{verdict}):\n#{content}"
      _ -> ""
    end
  end

  defp gather_tool_context(tools) do
    tools
    |> Enum.map(&execute_tool_for_context/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp execute_tool_for_context(tool) do
    case ReqLLM.Tool.execute(tool, %{}) do
      {:ok, result} -> to_string(result)
      _ -> ""
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp dangerous_tool_opts(thought) do
    loop_tools = Map.get(thought, :loop_tools)

    override =
      cond do
        is_list(loop_tools) and loop_tools != [] -> loop_tools
        is_list(loop_tools) -> :none
        true -> nil
      end

    Enum.reject(
      [
        dangerous_tool_mode: Map.get(thought, :dangerous_tool_mode) || "execute",
        rumination_id: Map.get(thought, :id),
        override_tools: override,
        max_tool_iterations: Map.get(thought, :max_tool_iterations)
      ],
      fn {_k, v} -> is_nil(v) end
    )
  end

  defp try_escalate_rank(rank, thought, augmented, threshold, escalate_on) do
    neurons = resolve_neurons(rank)

    if neurons == [] do
      {:cont, nil}
    else
      result = run(thought.roster, augmented, dangerous_tool_opts(thought))
      evaluate_escalate_result(result, threshold, escalate_on)
    end
  end

  defp evaluate_escalate_result({:ok, %{verdict: v, steps: steps}} = ok, threshold, escalate_on) do
    avg_confidence = average_step_confidence(steps)
    satisfied = avg_confidence >= threshold and v not in escalate_on
    if satisfied, do: {:halt, ok}, else: {:cont, ok}
  end

  defp evaluate_escalate_result(other, _threshold, _escalate_on), do: {:cont, other}

  defp average_step_confidence(steps) do
    steps
    |> Enum.flat_map(& &1.results)
    |> Enum.map(&Map.get(&1, :confidence, 0.5))
    |> then(fn
      [] -> 0.5
      cs -> Enum.sum(cs) / length(cs)
    end)
  end

  defp run_freeform_step(step, augmented, thought) do
    case resolve_neurons(step) do
      [] -> {:error, :no_roster}
      [neuron | _] -> run_freeform_member(neuron, augmented, thought)
    end
  end

  defp run_freeform_member(neuron, augmented, thought) do
    should_rollback = has_write_tools?(thought.loop_tools || [])
    if should_rollback, do: git_snapshot()

    case call_member_raw(neuron, augmented, dangerous_tool_opts(thought)) do
      {raw, tool_calls} when is_binary(raw) and raw != "" ->
        {:ok, %{output: raw, neuron: neuron.name, tool_calls: tool_calls}}

      {raw, tool_calls} when is_binary(raw) ->
        if should_rollback do
          Logger.info("[StepRunner] Empty response after tool iterations — rolling back")
          git_rollback()
        end

        {:ok, %{output: raw, neuron: neuron.name, tool_calls: tool_calls}}

      nil ->
        if should_rollback, do: git_rollback()
        {:error, :llm_failed}
    end
  end

  defp post_signal_cards(thought, attrs) do
    cards_spec = Map.get(thought, :cards) || %{}

    if cards_spec == %{} do
      post_single_signal_card(thought, attrs)
    else
      post_multi_signal_cards(thought, attrs, cards_spec)
    end
  end

  defp post_single_signal_card(thought, attrs) do
    card_type = attrs[:card_type] || parse_card_type(thought.description) || "note"

    card_attrs = %{
      type: card_type,
      card_type: card_type,
      title: attrs.title,
      body: attrs.body,
      tags: attrs[:tags] || [],
      source: "rumination",
      rumination_id: thought.id,
      metadata: attrs[:metadata] || %{},
      pin_slug: Map.get(thought, :pin_slug),
      pinned: Map.get(thought, :pinned, false),
      pin_order: Map.get(thought, :pin_order, 0),
      cluster_name: Map.get(thought, :cluster_name)
    }

    ExCortex.Signals.post_signal(card_attrs)
    {:ok, %{signal: card_attrs}}
  end

  defp post_multi_signal_cards(thought, attrs, cards_spec) do
    posted =
      Enum.map(cards_spec, fn spec ->
        card_attrs = %{
          type: spec["card_type"] || "briefing",
          card_type: spec["card_type"] || "briefing",
          title: attrs.title,
          body: attrs.body,
          tags: attrs[:tags] || [],
          source: "rumination",
          rumination_id: thought.id,
          metadata: attrs[:metadata] || %{},
          pin_slug: spec["pin_slug"],
          pinned: spec["pinned"] || false,
          pin_order: spec["pin_order"] || 0,
          cluster_name: Map.get(thought, :cluster_name)
        }

        ExCortex.Signals.post_signal(card_attrs)
      end)

    {:ok, %{signals: posted}}
  end

  defp default_claude_prompt do
    """
    You are a careful evaluator. Review the provided text and give your assessment.

    Respond with:
    ACTION: pass | warn | fail | abstain
    CONFIDENCE: 0.0-1.0
    REASON: your reasoning
    """
  end

  # ---------------------------------------------------------------------------
  # Artifact generation
  # ---------------------------------------------------------------------------

  defp run_artifact(thought, input_text) do
    roster = thought.roster || []

    case roster do
      [] ->
        {:error, :no_roster}

      [single_step] ->
        # Single step — original behaviour
        run_artifact_step(single_step, input_text, thought)

      steps ->
        # Multi-step: run all but last in reasoning mode, thread outputs to final step
        {prelim_steps, [final_step]} = Enum.split(steps, length(steps) - 1)
        reasoning_context = build_reasoning_context(prelim_steps, input_text)
        augmented = "#{input_text}\n\n---\n## Team Analysis\n#{reasoning_context}"
        run_artifact_step(final_step, augmented, thought)
    end
  end

  defp run_artifact_step(step, input_text, thought) do
    neurons = resolve_neurons(step)
    neuron = List.first(neurons)

    if is_nil(neuron) do
      {:error, :no_members}
    else
      system_prompt = artifact_system_prompt(thought)

      raw =
        case ExCortex.LLM.complete(neuron.provider, neuron.model, system_prompt, input_text) do
          {:ok, text} -> text
          _ -> nil
        end

      if raw do
        date = Calendar.strftime(Date.utc_today(), "%Y-%m-%d")
        title_template = thought.entry_title_template || thought.name || "Entry — {date}"
        title = String.replace(title_template, "{date}", date)
        {:ok, parse_artifact(raw, title)}
      else
        {:error, :llm_failed}
      end
    end
  end

  defp build_reasoning_context(prelim_steps, input_text) do
    Enum.map_join(prelim_steps, "\n\n", fn step ->
      label = step["label"] || step["who"] || "Analyst"
      member_outputs = build_step_member_outputs(step, input_text)
      "### #{label}\n#{member_outputs}"
    end)
  end

  defp build_step_member_outputs(step, input_text) do
    neurons = resolve_neurons(step)

    Enum.map_join(neurons, "\n\n", fn neuron ->
      reasoning_prompt = reasoning_system_prompt(neuron, step)

      text =
        case ExCortex.LLM.complete(neuron.provider, neuron.model, reasoning_prompt, input_text) do
          {:ok, t} -> t
          _ -> "(no response)"
        end

      "**#{neuron.name}:** #{String.slice(text, 0, 500)}"
    end)
  end

  defp reasoning_system_prompt(neuron, step) do
    base = neuron.system_prompt || ""
    label = step["label"] || neuron.name

    """
    #{base}

    You are #{label}. Provide your analysis and perspective on the data below.
    Be direct and opinionated. Your output will be read by a synthesizer.
    Do NOT use the TITLE/IMPORTANCE/TAGS/BODY format — just write your raw analysis.
    """
  end

  defp artifact_system_prompt(thought) do
    instruction = thought.description || "Synthesize the provided content."
    today = Calendar.strftime(Date.utc_today(), "%B %d, %Y")

    """
    Today's date is #{today}.

    #{instruction}

    Respond in this exact format:
    TITLE: <a concise title for this entry>
    IMPORTANCE: <integer 1-5, where 5 is most important, or omit if not applicable>
    TAGS: <comma-separated tags, lowercase, e.g. a11y,security,deps>
    BODY:
    <your synthesized content here, markdown is fine>
    """
  end

  defp parse_artifact(text, fallback_title) do
    %{
      title: parse_artifact_title(text, fallback_title),
      body: parse_artifact_body(text),
      tags: parse_artifact_tags(text),
      importance: parse_artifact_importance(text),
      card_type: parse_artifact_card_type(text),
      source: "step"
    }
  end

  defp parse_artifact_title(text, fallback_title) do
    case Regex.run(~r/^TITLE:\s*(.+)$/m, text) do
      [_, t] -> String.trim(t)
      _ -> fallback_title
    end
  end

  defp parse_artifact_importance(text) do
    case Regex.run(~r/^IMPORTANCE:\s*(\d)$/m, text) do
      [_, n] ->
        val = String.to_integer(n)
        if val in 1..5, do: val

      _ ->
        nil
    end
  end

  defp parse_artifact_tags(text) do
    case Regex.run(~r/^TAGS:\s*(.+)$/m, text) do
      [_, t] -> t |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
      _ -> []
    end
  end

  defp parse_artifact_body(text) do
    case Regex.run(~r/^BODY:\s*\n(.*)/ms, text) do
      [_, b] -> String.trim(b)
      _ -> text
    end
  end

  defp parse_artifact_card_type(text) do
    case Regex.run(~r/^CARD_TYPE:\s*(.+)$/m, text) do
      [_, ct] ->
        ct = ct |> String.trim() |> String.downcase()
        if ct in ~w(note checklist meeting alert link briefing action_list table media metric freeform), do: ct

      _ ->
        nil
    end
  end

  @valid_card_types ~w(note checklist meeting alert link briefing action_list table media metric freeform)
  defp parse_card_type(nil), do: nil
  defp parse_card_type(""), do: nil

  defp parse_card_type(description) when is_binary(description) do
    desc = String.downcase(description)
    Enum.find(@valid_card_types, fn type -> String.contains?(desc, type) end)
  end

  # ---------------------------------------------------------------------------
  # Git rollback helpers
  # ---------------------------------------------------------------------------

  defp git_snapshot do
    case System.cmd("git", ["stash", "create"], stderr_to_stdout: true) do
      {ref, 0} when ref != "" -> {:ok, String.trim(ref)}
      _ -> :no_snapshot
    end
  end

  defp git_rollback do
    Logger.info("[StepRunner] Rolling back uncommitted changes")
    System.cmd("git", ["checkout", "--", "."], stderr_to_stdout: true)

    System.cmd("git", ["clean", "-fd", "--exclude=_build", "--exclude=deps", "--exclude=.elixir_ls"],
      stderr_to_stdout: true
    )
  end
end
