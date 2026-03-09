defmodule ExCalibur.CampaignRunner do
  @moduledoc """
  Runs a Campaign's ordered quest steps in sequence.

  Each step's output is formatted as text and prepended to the next step's
  input as additional context. The final step's result is returned.

  Steps are maps: %{"quest_id" => "123", "order" => 1}
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
    ordered_steps =
      campaign.steps
      |> Enum.sort_by(&Map.get(&1, "order", 0))

    Logger.info(
      "[CampaignRunner] Running campaign #{campaign.id} (#{campaign.name}), #{length(ordered_steps)} step(s)"
    )

    {results, _accumulated_context} =
      Enum.reduce(ordered_steps, {[], input}, fn step, {acc_results, current_input} ->
        quest_id = step["quest_id"]

        case resolve_quest(quest_id) do
          nil ->
            Logger.warning("[CampaignRunner] Quest #{quest_id} not found, skipping step")
            {acc_results ++ [{:error, :quest_not_found}], current_input}

          quest ->
            Logger.info("[CampaignRunner] Running step quest #{quest.id} (#{quest.name})")
            result = QuestRunner.run(quest, current_input)

            # Thread output as extra context for the next step
            next_input =
              case result_to_text(result) do
                "" -> current_input
                text -> "#{current_input}\n\n---\n## Previous Step: #{quest.name}\n#{text}"
              end

            {acc_results ++ [result], next_input}
        end
      end)

    last_result = List.last(results)

    case last_result do
      {:ok, _} = ok -> ok
      _ -> {:ok, %{steps: results}}
    end
  end

  @doc "Format a QuestRunner result as a plain text string for context threading."
  def result_to_text({:ok, %{artifact: %{title: title, body: body}}}) do
    "# #{title}\n#{body}"
  end

  def result_to_text({:ok, %{verdict: verdict, steps: steps}}) do
    summary = Enum.map_join(steps, "\n", fn s -> "- #{s.who}: #{s.verdict}" end)
    "Verdict: #{verdict}\n#{summary}"
  end

  def result_to_text({:ok, %{delivered: true, type: type}}) do
    "Herald delivered (#{type})"
  end

  def result_to_text(_), do: ""

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
end
