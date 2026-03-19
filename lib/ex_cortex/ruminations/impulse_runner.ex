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
  alias ExCortex.Ruminations.ImpulseRunner.Artifact
  alias ExCortex.Ruminations.ImpulseRunner.Consensus
  alias ExCortex.Ruminations.ImpulseRunner.Escalation
  alias ExCortex.Ruminations.ImpulseRunner.Reflect
  alias ExCortex.Ruminations.Middleware
  alias ExCortex.Ruminations.RosterResolver

  require Logger

  @rank_order %{"apprentice" => 0, "journeyman" => 1, "master" => 2}

  @expression_types ~w(slack webhook github_issue github_pr email pagerduty)

  @dangerous_tools ~w(send_email create_github_issue comment_github run_rumination merge_pr git_pull restart_app close_issue nextcloud_talk email_archive_year email_classify email_tag email_move)
  @write_tool_names ~w(write_file edit_file git_commit create_obsidian_note daily_note_write)

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

  # Default opts for all struct/map run clauses
  def run(thought_or_roster, input_text, opts \\ [])

  # Reflect mode — run neurons, if unsatisfied gather context via tools and retry
  def run(%{loop_mode: "reflect"} = thought, input_text, opts) do
    with_middleware(thought, input_text, opts, fn augmented, _middleware ->
      threshold = thought.reflect_threshold || 0.6
      reflect_on = thought.reflect_on_verdict || []
      max_iter = thought.max_iterations || 3
      tools = ExCortex.Tools.Registry.resolve_tools(thought.loop_tools || [])
      Reflect.do_reflect(thought, augmented, tools, threshold, reflect_on, max_iter, 0)
    end)
  end

  # Escalate mode — try ranks in order until result is satisfying
  def run(%{escalate: true} = thought, input_text, opts) do
    with_middleware(thought, input_text, opts, fn augmented, _middleware ->
      threshold = thought.escalate_threshold || 0.6
      escalate_on = thought.escalate_on_verdict || []

      ["apprentice", "journeyman", "master"]
      |> Enum.reduce_while(nil, fn rank, _acc ->
        Escalation.try_escalate_rank(rank, thought, augmented, threshold, escalate_on)
      end)
      |> then(fn
        nil -> {:ok, %{verdict: "abstain", steps: []}}
        result -> result
      end)
    end)
  end

  def run(%{min_rank: min_rank} = thought, input_text, opts) when is_binary(min_rank) and min_rank != "" do
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
      with_middleware(thought, input_text, opts, fn augmented, middleware ->
        run(thought.roster, augmented, dangerous_tool_opts(thought) ++ [middleware: middleware])
      end)
    else
      {:error, {:rank_insufficient, "Step requires #{min_rank} or higher — no eligible neurons found"}}
    end
  end

  def run(%{output_type: type} = thought, input_text, opts) when type in @expression_types do
    with_middleware(thought, input_text, opts, fn augmented, _middleware ->
      with {:ok, expression} <- ExCortex.Expressions.get_by_name(thought.expression_name || ""),
           {:ok, attrs} <- Artifact.run_artifact(thought, augmented),
           :ok <- ExCortex.Expressions.deliver(expression, thought, attrs) do
        {:ok, %{delivered: true, type: type, title: attrs.title}}
      end
    end)
  end

  def run(%{output_type: "artifact"} = thought, input_text, opts) do
    with_middleware(thought, input_text, opts, fn augmented, _middleware ->
      case Artifact.run_artifact(thought, augmented) do
        {:ok, attrs} ->
          forced_tags = thought.engram_tags || []
          attrs = Map.update(attrs, :tags, forced_tags, &Enum.uniq(&1 ++ forced_tags))
          ExCortex.Memory.write_artifact(thought, attrs)
          {:ok, %{artifact: attrs}}

        error ->
          error
      end
    end)
  end

  def run(%{output_type: "freeform"} = thought, input_text, opts) do
    with_middleware(thought, input_text, opts, fn augmented, _middleware ->
      roster = thought.roster || []

      case roster do
        [] -> {:error, :no_roster}
        [step | _] -> run_freeform_step(step, augmented, thought)
      end
    end)
  end

  def run(%{output_type: "signal"} = thought, input_text, opts) do
    with_middleware(thought, input_text, opts, fn augmented, _middleware ->
      case Artifact.run_artifact(thought, augmented) do
        {:ok, attrs} -> Artifact.post_signal_cards(thought, attrs)
        error -> error
      end
    end)
  end

  def run(thought, input_text, opts) when is_struct(thought) do
    with_middleware(thought, input_text, opts, fn augmented, middleware ->
      run(thought.roster, augmented, dangerous_tool_opts(thought) ++ [middleware: middleware])
    end)
  end

  def run(roster, input_text, opts) when is_list(roster) do
    {steps, final_verdict} =
      Enum.reduce_while(roster, {[], nil}, fn step, {traces, _prev_verdict} ->
        neurons = resolve_neurons(step)

        synapse_results = run_step(neurons, step["how"], input_text, opts)

        laterality = ExCortex.Lobe.laterality_for_cluster(step["cluster_name"])
        step_verdict = Consensus.aggregate(synapse_results, step["how"], laterality)

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
  # Public helpers used by submodules
  # ---------------------------------------------------------------------------

  @doc false
  def dangerous_tool_opts(thought) do
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

  # ---------------------------------------------------------------------------
  # Neuron resolution — delegated to RosterResolver
  # ---------------------------------------------------------------------------

  defp resolve_neurons(step_or_who), do: RosterResolver.resolve(step_or_who)

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
      names when is_list(names) and names != [] -> ExCortex.Tools.Registry.resolve_tools(names)
      _ -> member_tools
    end
  end

  defp call_member(
         %{provider: provider, model: model, system_prompt: system_prompt, tools: member_tools} = neuron,
         input_text,
         opts
       ) do
    tools = effective_tools(member_tools, opts)

    lobe_prefix =
      case ExCortex.Lobe.prompt_for_cluster(neuron[:team]) do
        nil -> ""
        lp -> "[#{lp}]\n\n"
      end

    base = lobe_prefix <> (system_prompt || default_claude_prompt())
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
        text |> Consensus.parse_verdict() |> Map.put(:tool_calls, tool_log)

      {:ok, text} ->
        require Logger

        Logger.debug("[StepRunner] raw response (#{byte_size(text)}B): #{String.slice(text, 0, 300)}")
        text |> Consensus.parse_verdict() |> Map.put(:tool_calls, [])

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
  # Freeform helpers
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Middleware helpers
  # ---------------------------------------------------------------------------

  defp with_middleware(thought, input_text, opts, fun) do
    middleware = Middleware.resolve(Map.get(thought, :middleware) || [])
    context = ContextProvider.assemble(thought.context_providers || [], thought, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    mw_ctx = %Middleware.Context{
      synapse: thought,
      daydream: Keyword.get(opts, :daydream),
      input_text: augmented,
      neurons: nil,
      metadata: %{
        trust_level: Keyword.get(opts, :trust_level),
        source_type: Keyword.get(opts, :source_type)
      }
    }

    case Middleware.run_before(middleware, mw_ctx, []) do
      {:halt, reason} ->
        {:error, {:middleware_halted, reason}}

      {:cont, updated_ctx} ->
        result = fun.(updated_ctx.input_text, middleware)
        Middleware.run_after(middleware, updated_ctx, result, [])
    end
  end
end
