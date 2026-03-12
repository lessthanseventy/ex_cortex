defmodule ExCalibur.StepRunner do
  @moduledoc """
  Runs a Step's roster against input text, returning a trace of verdicts.

  ## Roster step format
    %{
      "who"         => "all" | "apprentice" | "journeyman" | "master" | "team:X" | member_id | "claude_haiku" | "claude_sonnet" | "claude_opus",
      "when"        => "parallel" | "sequential",
      "how"         => "consensus" | "solo" | "majority",
      "escalate_on" => "never" | "always" | %{"type" => "verdict", "values" => [...]} | %{"type" => "confidence", "threshold" => float}
    }

  ## Return value
    {:ok, %{verdict: "pass"|"warn"|"fail", steps: [step_trace, ...]}}
    {:error, reason}
  """

  import Ecto.Query

  alias ExCalibur.ContextProviders.ContextProvider
  alias ExCalibur.Repo
  alias Excellence.Schemas.Member

  @verdict_order %{"fail" => 0, "warn" => 1, "abstain" => 2, "pass" => 3}
  @rank_order %{"apprentice" => 0, "journeyman" => 1, "master" => 2}

  @herald_types ~w(slack webhook github_issue github_pr email pagerduty)

  @dangerous_tools ~w(send_email create_github_issue comment_github run_quest)

  def dangerous?(tool_name), do: tool_name in @dangerous_tools

  def intercept_dangerous_tool(tool_name, tool_args, quest_id, context \\ nil) do
    ExCalibur.Quests.create_proposal(%{
      quest_id: quest_id,
      type: "tool_action",
      description: "Tool call: #{tool_name}",
      details: %{"suggestion" => context || "Automated tool call"},
      status: "pending",
      tool_name: tool_name,
      tool_args: tool_args,
      context: context
    })
  end

  @doc "Build the ordered list of models to try: assigned model first, then fallback chain (deduped)."
  defdelegate fallback_models_for(model, chain), to: ExCalibur.LLM.Ollama

  @doc """
  Run a step roster against `input_text`.
  Accepts either a `Step` struct or just a bare roster list.
  Returns `{:ok, result}` or `{:error, reason}`.
  """

  # Reflect mode — run members, if unsatisfied gather context via tools and retry
  def run(%{loop_mode: "reflect"} = quest, input_text) do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    threshold = quest.reflect_threshold || 0.6
    reflect_on = quest.reflect_on_verdict || []
    max_iter = quest.max_iterations || 3
    tools = ExCalibur.Tools.Registry.resolve_tools(quest.loop_tools || [])

    do_reflect(quest, augmented, tools, threshold, reflect_on, max_iter, 0)
  end

  # Escalate mode — try ranks in order until result is satisfying
  def run(%{escalate: true} = quest, input_text) do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    threshold = quest.escalate_threshold || 0.6
    escalate_on = quest.escalate_on_verdict || []

    ["apprentice", "journeyman", "master"]
    |> Enum.reduce_while(nil, fn rank, _acc ->
      members = resolve_members(rank)

      if members == [] do
        {:cont, nil}
      else
        result = run(quest.roster, augmented)

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

            satisfied = avg_confidence >= threshold and v not in escalate_on
            if satisfied, do: {:halt, ok}, else: {:cont, ok}

          other ->
            {:cont, other}
        end
      end
    end)
    |> then(fn
      nil -> {:ok, %{verdict: "abstain", steps: []}}
      result -> result
    end)
  end

  def run(%{min_rank: min_rank} = quest, input_text) when is_binary(min_rank) and min_rank != "" do
    min_order = Map.get(@rank_order, min_rank, 0)

    eligible_ranks =
      @rank_order
      |> Enum.filter(fn {_rank, order} -> order >= min_order end)
      |> Enum.map(fn {rank, _} -> rank end)

    has_eligible =
      Repo.exists?(
        from m in Member,
          where:
            m.type == "role" and m.status == "active" and
              fragment("config->>'rank' = ANY(?)", ^eligible_ranks)
      )

    if has_eligible do
      context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
      augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"
      run(quest.roster, augmented)
    else
      {:error, {:rank_insufficient, "Step requires #{min_rank} or higher — no eligible members found"}}
    end
  end

  def run(%{output_type: type} = quest, input_text) when type in @herald_types do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    with {:ok, herald} <- ExCalibur.Heralds.get_by_name(quest.herald_name || ""),
         {:ok, attrs} <- run_artifact(quest, augmented),
         :ok <- ExCalibur.Heralds.deliver(herald, quest, attrs) do
      {:ok, %{delivered: true, type: type, title: attrs.title}}
    end
  end

  def run(%{output_type: "artifact"} = quest, input_text) do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"
    result = run_artifact(quest, augmented)

    case result do
      {:ok, attrs} ->
        forced_tags = quest.lore_tags || []
        attrs = Map.update(attrs, :tags, forced_tags, &Enum.uniq(&1 ++ forced_tags))
        ExCalibur.Lore.write_artifact(quest, attrs)
        {:ok, %{artifact: attrs}}

      error ->
        error
    end
  end

  def run(%{output_type: "freeform"} = quest, input_text) do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    roster = quest.roster || []

    with [step | _] <- roster,
         [member | _] <- resolve_members(step),
         raw when is_binary(raw) <- call_member_raw(member, augmented) do
      {:ok, %{output: raw, member: member.name}}
    else
      [] -> {:error, :no_roster}
      nil -> {:error, :llm_failed}
      error -> error
    end
  end

  def run(%{output_type: "lodge_card"} = quest, input_text) do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"

    case run_artifact(quest, augmented) do
      {:ok, attrs} ->
        card_type = attrs[:card_type] || parse_card_type(quest.description) || "note"

        card_attrs = %{
          type: card_type,
          title: attrs.title,
          body: attrs.body,
          tags: attrs[:tags] || [],
          source: "quest",
          quest_id: quest[:id],
          metadata: attrs[:metadata] || %{}
        }

        ExCalibur.Lodge.post_card(card_attrs)
        {:ok, %{lodge_card: card_attrs}}

      error ->
        error
    end
  end

  def run(quest, input_text) when is_struct(quest) do
    context = ContextProvider.assemble(quest.context_providers || [], quest, input_text)
    augmented = if context == "", do: input_text, else: "#{context}\n\n#{input_text}"
    run(quest.roster, augmented)
  end

  def run(roster, input_text) when is_list(roster) do
    {steps, final_verdict} =
      Enum.reduce_while(roster, {[], nil}, fn step, {traces, _prev_verdict} ->
        members = resolve_members(step)

        step_results = run_step(members, step["how"], input_text)

        step_verdict = aggregate(step_results, step["how"])

        trace = %{
          who: step["who"],
          how: step["how"],
          results: step_results,
          verdict: step_verdict
        }

        if should_escalate?(step["escalate_on"], step_verdict) do
          {:halt, {traces ++ [trace], step_verdict}}
        else
          {:cont, {traces ++ [trace], step_verdict}}
        end
      end)

    result = {:ok, %{verdict: final_verdict || "pass", steps: steps}}
    ExCalibur.TrustScorer.record_run(steps)
    result
  end

  # ---------------------------------------------------------------------------
  # Member resolution
  # ---------------------------------------------------------------------------

  defp resolve_members(%{"preferred_who" => name} = step) when is_binary(name) and name != "" do
    case from(m in Member,
           where: m.type == "role" and m.status == "active" and m.name == ^name
         )
         |> Repo.all()
         |> Enum.map(&member_to_runner_spec/1) do
      [] -> resolve_members(%{step | "preferred_who" => nil})
      members -> members
    end
  end

  defp resolve_members(%{"who" => who}), do: resolve_members(who)
  defp resolve_members(step) when is_map(step), do: resolve_members(Map.get(step, "who", "all"))

  defp resolve_members("all") do
    from(m in Member, where: m.type == "role" and m.status == "active")
    |> Repo.all()
    |> Enum.map(&member_to_runner_spec/1)
  end

  defp resolve_members("apprentice"), do: resolve_by_rank("apprentice")

  defp resolve_members("journeyman"), do: resolve_by_rank("journeyman")

  defp resolve_members("master"), do: resolve_by_rank("master")

  defp resolve_members("challenger") do
    case ExCalibur.Members.BuiltinMember.get("challenger") do
      nil ->
        []

      member ->
        rank_config = member.ranks[:journeyman]

        [
          %{
            provider: "ollama",
            model: rank_config.model,
            system_prompt: member.system_prompt,
            name: member.name,
            tools: []
          }
        ]
    end
  end

  defp resolve_members("team:" <> team) do
    from(m in Member,
      where: m.type == "role" and m.status == "active" and m.team == ^team
    )
    |> Repo.all()
    |> Enum.map(&member_to_runner_spec/1)
  end

  defp resolve_members(claude_tier) when claude_tier in ["claude_haiku", "claude_sonnet", "claude_opus"] do
    [%{provider: "claude", model: claude_tier, name: claude_tier, system_prompt: nil, tools: []}]
  end

  defp resolve_members(member_id) when is_binary(member_id) do
    case Repo.get(Member, member_id) do
      nil -> []
      m -> [member_to_runner_spec(m)]
    end
  end

  defp resolve_by_rank(rank) do
    from(m in Member,
      where:
        m.type == "role" and m.status == "active" and
          fragment("config->>'rank' = ?", ^rank)
    )
    |> Repo.all()
    |> Enum.map(&member_to_runner_spec/1)
  end

  defp member_to_runner_spec(db) do
    %{
      provider: db.config["provider"] || "ollama",
      model: db.config["model"] || "phi4-mini",
      system_prompt: db.config["system_prompt"] || "",
      name: db.name,
      tools: resolve_member_tools(db.config["tools"])
    }
  end

  defp resolve_member_tools(nil), do: []
  defp resolve_member_tools("all_safe"), do: ExCalibur.Tools.Registry.resolve_tools(:all_safe)
  defp resolve_member_tools("write"), do: ExCalibur.Tools.Registry.resolve_tools(:write)
  defp resolve_member_tools("dangerous"), do: ExCalibur.Tools.Registry.resolve_tools(:dangerous)
  defp resolve_member_tools("yolo"), do: ExCalibur.Tools.Registry.resolve_tools(:dangerous)
  defp resolve_member_tools(names) when is_list(names), do: ExCalibur.Tools.Registry.resolve_tools(names)
  defp resolve_member_tools(_), do: []

  # ---------------------------------------------------------------------------
  # Running a step
  # ---------------------------------------------------------------------------

  defp run_step(members, _how, input_text) do
    Enum.map(members, fn member ->
      result = call_member(member, input_text)
      Map.put(result, :member, member.name)
    end)
  end

  defp call_member(%{provider: provider, model: model, system_prompt: system_prompt, tools: tools}, input_text) do
    prompt = system_prompt || default_claude_prompt()

    result =
      if tools == [] do
        ExCalibur.LLM.complete(provider, model, prompt, input_text)
      else
        ExCalibur.LLM.complete_with_tools(provider, model, prompt, input_text, tools)
      end

    case result do
      {:ok, text} -> parse_verdict(text)
      {:error, _} -> %{verdict: "abstain", confidence: 0.0, reason: "LLM error (#{provider})"}
    end
  end

  # Like call_member but returns raw text — used for freeform quests.
  defp call_member_raw(%{provider: provider, model: model, system_prompt: system_prompt, tools: tools}, input_text) do
    prompt = system_prompt || ""

    result =
      if tools == [] do
        ExCalibur.LLM.complete(provider, model, prompt, input_text)
      else
        ExCalibur.LLM.complete_with_tools(provider, model, prompt, input_text, tools)
      end

    case result do
      {:ok, text} -> text
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

  defp do_reflect(quest, input_text, _tools, _threshold, _reflect_on, max_iter, iter) when iter >= max_iter do
    run(quest.roster, input_text)
  end

  defp do_reflect(quest, input_text, tools, threshold, reflect_on, max_iter, iter) do
    result = run(quest.roster, input_text)

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
          do_reflect(quest, augmented, tools, threshold, reflect_on, max_iter, iter + 1)
        end

      other ->
        other
    end
  end

  defp gather_reflect_context(tools, verdict) do
    lore_tool = Enum.find(tools, &(&1.name == "query_lore"))

    if lore_tool do
      case ReqLLM.Tool.execute(lore_tool, %{"tags" => [], "limit" => 3}) do
        {:ok, content} -> "Prior lore context (verdict was #{verdict}):\n#{content}"
        _ -> ""
      end
    else
      tools
      |> Enum.map(fn tool ->
        case ReqLLM.Tool.execute(tool, %{}) do
          {:ok, result} -> to_string(result)
          _ -> ""
        end
      end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

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

  defp run_artifact(quest, input_text) do
    roster = quest.roster || []

    case roster do
      [] ->
        {:error, :no_roster}

      [single_step] ->
        # Single step — original behaviour
        run_artifact_step(single_step, input_text, quest)

      steps ->
        # Multi-step: run all but last in reasoning mode, thread outputs to final step
        {prelim_steps, [final_step]} = Enum.split(steps, length(steps) - 1)

        reasoning_context =
          Enum.map_join(prelim_steps, "\n\n", fn step ->
            members = resolve_members(step)
            label = step["label"] || step["who"] || "Analyst"

            member_outputs =
              Enum.map_join(members, "\n\n", fn member ->
                reasoning_prompt = reasoning_system_prompt(member, step)

                text =
                  case ExCalibur.LLM.complete(member.provider, member.model, reasoning_prompt, input_text) do
                    {:ok, t} -> t
                    _ -> "(no response)"
                  end

                "**#{member.name}:** #{String.slice(text, 0, 500)}"
              end)

            "### #{label}\n#{member_outputs}"
          end)

        augmented = "#{input_text}\n\n---\n## Team Analysis\n#{reasoning_context}"
        run_artifact_step(final_step, augmented, quest)
    end
  end

  defp run_artifact_step(step, input_text, quest) do
    members = resolve_members(step)
    member = List.first(members)

    if is_nil(member) do
      {:error, :no_members}
    else
      system_prompt = artifact_system_prompt(quest)

      raw =
        case ExCalibur.LLM.complete(member.provider, member.model, system_prompt, input_text) do
          {:ok, text} -> text
          _ -> nil
        end

      if raw do
        date = Calendar.strftime(Date.utc_today(), "%Y-%m-%d")
        title_template = quest.entry_title_template || quest.name || "Entry — {date}"
        title = String.replace(title_template, "{date}", date)
        {:ok, parse_artifact(raw, title)}
      else
        {:error, :llm_failed}
      end
    end
  end

  defp reasoning_system_prompt(member, step) do
    base = member.system_prompt || ""
    label = step["label"] || member.name

    """
    #{base}

    You are #{label}. Provide your analysis and perspective on the data below.
    Be direct and opinionated. Your output will be read by a synthesizer.
    Do NOT use the TITLE/IMPORTANCE/TAGS/BODY format — just write your raw analysis.
    """
  end

  defp artifact_system_prompt(quest) do
    instruction = quest.description || "Synthesize the provided content."
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
    title =
      case Regex.run(~r/^TITLE:\s*(.+)$/m, text) do
        [_, t] -> String.trim(t)
        _ -> fallback_title
      end

    importance =
      case Regex.run(~r/^IMPORTANCE:\s*(\d)$/m, text) do
        [_, n] ->
          val = String.to_integer(n)
          if val in 1..5, do: val

        _ ->
          nil
      end

    tags =
      case Regex.run(~r/^TAGS:\s*(.+)$/m, text) do
        [_, t] ->
          t |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

        _ ->
          []
      end

    body =
      case Regex.run(~r/^BODY:\s*\n(.*)/ms, text) do
        [_, b] -> String.trim(b)
        _ -> text
      end

    card_type =
      case Regex.run(~r/^CARD_TYPE:\s*(.+)$/m, text) do
        [_, ct] ->
          ct = ct |> String.trim() |> String.downcase()
          if ct in ~w(note checklist meeting alert link briefing action_list table media metric freeform), do: ct

        _ ->
          nil
      end

    %{title: title, body: body, tags: tags, importance: importance, card_type: card_type, source: "step"}
  end

  @valid_card_types ~w(note checklist meeting alert link briefing action_list table media metric freeform)
  defp parse_card_type(nil), do: nil
  defp parse_card_type(""), do: nil

  defp parse_card_type(description) when is_binary(description) do
    desc = String.downcase(description)
    Enum.find(@valid_card_types, fn type -> String.contains?(desc, type) end)
  end
end
