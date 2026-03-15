defmodule ExCortex.Tools.RunThought do
  @moduledoc "Tool: run a thought by name with a given input string."

  import Ecto.Query

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "run_quest",
      description: "Run a named thought with the given input text. Returns the thought result.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "thought_name" => %{"type" => "string", "description" => "The name of the thought to run"},
          "input" => %{
            "type" => "string",
            "description" => "The input text to pass to the thought"
          }
        },
        "required" => ["thought_name", "input"]
      },
      callback: &call/1
    )
  end

  def call(%{"thought_name" => name, "input" => input}) do
    alias ExCortex.Thoughts.Thought

    case ExCortex.Repo.one(from q in Thought, where: q.name == ^name, limit: 1) do
      nil ->
        {:error, "Thought '#{name}' not found"}

      thought ->
        preloaded = ExCortex.Repo.preload(thought, :steps)

        case ExCortex.Thoughts.Runner.run(preloaded, input) do
          {:ok, result} -> {:ok, inspect(result)}
          other -> {:error, inspect(other)}
        end
    end
  end
end
