defmodule ExCalibur.CampaignRunner do
  @moduledoc """
  Runs a Campaign's ordered quest steps in sequence.

  Each step's output is formatted as a structured handoff block and prepended
  to the next step's input. The final step's result is returned.

  Steps are maps: %{"quest_id" => "123", "order" => 1}
  Branch steps: %{"type" => "branch", "quests" => [...], "synthesizer" => "...", "order" => 1}
  """

  alias ExCalibur.QuestRunner
  alias ExCalibur.Quests

  require Logger

  @doc "Run all steps of a campaign, returning the final step result."
  def run(%{steps: steps} = campaign, _input) when steps == [] do
    Logger.info("[CampaignRunner] Campaign #{campaign.id} (#{campaign.name}) has no steps")
    {:ok, %{steps: []}}
  end

  def run(campaign, input) do
    ordered_steps = Enum.sort_by(campaign.steps, &Map.get(&1, "order", 0))

    Logger.info(
      "[CampaignRunner] Running campaign #{campaign.id} (#{campaign.name}), #{length(ordered_steps)} step(s)"
    )

    # Zip each step with the next step for look-ahead (next quest name for handoff)
    steps_with_next = Enum.zip(ordered_steps, tl(ordered_steps) ++ [nil])

    {results, _} =
      Enum.reduce(steps_with_next, {[], input}, fn {step, next_step}, {acc_results, current_input} ->
        case step["type"] do
          "branch" ->
            next_quest_name =
              if next_step,
                do: resolve_quest_name(next_step["quest_id"] || next_step["synthesizer"]),
                else: nil

            result = run_branch_step(step, current_input)

            synth_quest_name =
              case resolve_quest(step["synthesizer"]) do
                nil -> "Branch"
                q -> q.name
              end

            next_input =
              case result_to_text(result, "Branch: #{synth_quest_name}", next_quest_name) do
                "" -> current_input
                text -> "#{current_input}\n\n#{text}"
              end

            {acc_results ++ [result], next_input}

          _ ->
            quest_id = step["quest_id"]
            next_quest_name = if next_step, do: resolve_quest_name(next_step["quest_id"]), else: nil

            case resolve_quest(quest_id) do
              nil ->
                Logger.warning("[CampaignRunner] Quest #{quest_id} not found, skipping step")
                {acc_results ++ [{:error, :quest_not_found}], current_input}

              quest ->
                Logger.info("[CampaignRunner] Running step quest #{quest.id} (#{quest.name})")
                result = QuestRunner.run(quest, current_input)

                next_input =
                  case result_to_text(result, quest.name, next_quest_name) do
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

  @doc "Format a QuestRunner result as a structured handoff block for the next step."
  def result_to_text(result, current_quest_name, next_quest_name)

  def result_to_text({:ok, %{verdict: verdict, steps: steps}}, quest_name, next_quest_name) do
    member_lines =
      steps
      |> Enum.flat_map(& &1.results)
      |> Enum.map_join("\n", fn r ->
        "- **#{r.member}:** #{r.verdict} — #{String.slice(r[:reason] || "", 0, 120)}"
      end)

    question =
      if next_quest_name,
        do:
          "\n**Open question for #{next_quest_name}:** What does this verdict imply for your evaluation?",
        else: ""

    """
    ## Prior Step: #{quest_name}
    **Verdict:** #{verdict}
    **Member findings:**
    #{member_lines}#{question}
    """
  end

  def result_to_text(
        {:ok, %{artifact: %{title: title, body: body}}},
        quest_name,
        next_quest_name
      ) do
    question =
      if next_quest_name,
        do:
          "\n**Open question for #{next_quest_name}:** How does this artifact inform your evaluation?",
        else: ""

    """
    ## Prior Step: #{quest_name}
    **Artifact:** #{title}
    #{body}#{question}
    """
  end

  def result_to_text({:ok, %{delivered: true, type: type}}, quest_name, _next) do
    "## Prior Step: #{quest_name}\nHerald delivered (#{type})\n"
  end

  def result_to_text(_, _, _), do: ""

  # Keep arity-1 version for backwards compatibility
  def result_to_text(result), do: result_to_text(result, "Previous Step", nil)

  @doc "Combine parallel branch results into a single context block for the synthesizer."
  def combine_branch_results(named_results, original_input) do
    branch_context =
      named_results
      |> Enum.map_join("\n\n", fn {name, result} ->
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
    quest_ids = step["quests"] || []
    synthesizer_id = step["synthesizer"]

    Logger.info(
      "[CampaignRunner] Running branch step: #{length(quest_ids)} parallel quest(s) + synthesizer"
    )

    branch_results =
      quest_ids
      |> Task.async_stream(
        fn quest_id ->
          case resolve_quest(quest_id) do
            nil ->
              {quest_id, {:error, :quest_not_found}}

            quest ->
              Logger.info("[CampaignRunner] Branch: running #{quest.name}")
              {quest.name, QuestRunner.run(quest, input)}
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

    case resolve_quest(synthesizer_id) do
      nil ->
        Logger.warning("[CampaignRunner] Branch synthesizer #{synthesizer_id} not found")
        {:error, :synthesizer_not_found}

      synth ->
        Logger.info("[CampaignRunner] Branch: running synthesizer #{synth.name}")
        QuestRunner.run(synth, combined_input)
    end
  end

  defp resolve_quest_name(quest_id) when is_binary(quest_id) do
    case resolve_quest(quest_id) do
      nil -> quest_id
      quest -> quest.name
    end
  end

  defp resolve_quest_name(_), do: nil

  defp resolve_quest(quest_id) when is_binary(quest_id) do
    case Integer.parse(quest_id) do
      {id, ""} -> Quests.get_quest!(id)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp resolve_quest(quest_id) when is_integer(quest_id) do
    Quests.get_quest!(quest_id)
  rescue
    _ -> nil
  end

  defp resolve_quest(_), do: nil
end
