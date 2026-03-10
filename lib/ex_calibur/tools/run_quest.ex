defmodule ExCalibur.Tools.RunQuest do
  @moduledoc "Tool: run a quest by name with a given input string."

  import Ecto.Query

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "run_quest",
      description: "Run a named quest with the given input text. Returns the quest result.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "quest_name" => %{"type" => "string", "description" => "The name of the quest to run"},
          "input" => %{
            "type" => "string",
            "description" => "The input text to pass to the quest"
          }
        },
        "required" => ["quest_name", "input"]
      },
      callback: &call/1
    )
  end

  def call(%{"quest_name" => name, "input" => input}) do
    alias ExCalibur.Quests.Quest

    case ExCalibur.Repo.one(from q in Quest, where: q.name == ^name, limit: 1) do
      nil ->
        {:error, "Quest '#{name}' not found"}

      quest ->
        preloaded = ExCalibur.Repo.preload(quest, :steps)

        case ExCalibur.QuestRunner.run(preloaded, input) do
          {:ok, result} -> {:ok, inspect(result)}
          other -> {:error, inspect(other)}
        end
    end
  end
end
