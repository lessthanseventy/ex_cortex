defmodule ExCalibur.ContextProviders.QuestOutput do
  @moduledoc """
  Injects the output of the most recent completed run of a named quest.

  Config:
    "quest"              - quest name to look up (required)
    "steps"              - list of step indices to include, e.g. [0, 1] (default: all)
    "label"              - section header
    "max_bytes_per_step" - per-step output truncation (default: 2000)

  Example:
    %{"type" => "quest_output", "quest" => "SI: Analyst Sweep", "steps" => [0, 1]}
  """

  @behaviour ExCalibur.ContextProviders.ContextProvider

  import Ecto.Query

  alias ExCalibur.Quests.Quest
  alias ExCalibur.Quests.QuestRun
  alias ExCalibur.Repo

  require Logger

  @default_max_bytes 2_000

  @impl true
  def build(config, _quest, _input) do
    case Map.get(config, "quest") do
      nil ->
        Logger.warning("[QuestOutputCtx] No 'quest' name in config")
        ""

      quest_name ->
        fetch_output(quest_name, config)
    end
  end

  defp fetch_output(quest_name, config) do
    label = Map.get(config, "label", "## Previous Quest Output: #{quest_name}")
    step_indices = Map.get(config, "steps")
    max_bytes = Map.get(config, "max_bytes_per_step", @default_max_bytes)

    with %Quest{id: quest_id} <- Repo.one(from q in Quest, where: q.name == ^quest_name, limit: 1),
         %QuestRun{step_results: results} <- latest_run(quest_id) do
      format_output(label, results, step_indices, max_bytes)
    else
      nil ->
        Logger.debug("[QuestOutputCtx] No completed run found for quest: #{quest_name}")
        ""
    end
  end

  defp latest_run(quest_id) do
    Repo.one(
      from r in QuestRun,
        where: r.quest_id == ^quest_id and r.status == "complete",
        order_by: [desc: r.inserted_at],
        limit: 1
    )
  end

  defp format_output(label, step_results, nil, max_bytes) do
    indices =
      step_results
      |> Map.keys()
      |> Enum.map(&String.to_integer/1)
      |> Enum.sort()

    format_output(label, step_results, indices, max_bytes)
  end

  defp format_output(label, step_results, indices, max_bytes) do
    sections =
      Enum.flat_map(indices, fn idx ->
        case Map.get(step_results, to_string(idx)) do
          %{"data" => data, "status" => status} when is_binary(data) ->
            truncated = String.slice(data, 0, max_bytes)
            suffix = if byte_size(data) > max_bytes, do: "\n... (truncated)", else: ""
            ["### Step #{idx} (#{status})\n#{truncated}#{suffix}"]

          _ ->
            []
        end
      end)

    if sections == [] do
      ""
    else
      "#{label}\n\n#{Enum.join(sections, "\n\n")}"
    end
  end
end
