defmodule ExCortex.Tools.RunRumination do
  @moduledoc "Tool: run a rumination by name with a given input string."

  import Ecto.Query

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "run_rumination",
      description: "Run a named rumination with the given input text. Returns the rumination result.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "rumination_name" => %{"type" => "string", "description" => "The name of the rumination to run"},
          "input" => %{
            "type" => "string",
            "description" => "The input text to pass to the rumination"
          }
        },
        "required" => ["rumination_name", "input"]
      },
      callback: &call/1
    )
  end

  def call(%{"rumination_name" => name, "input" => input}) do
    alias ExCortex.Ruminations.Rumination

    case ExCortex.Repo.one(from q in Rumination, where: q.name == ^name, limit: 1) do
      nil ->
        {:error, "Rumination '#{name}' not found"}

      rumination ->
        preloaded = ExCortex.Repo.preload(rumination, :steps)

        case ExCortex.Ruminations.Runner.run(preloaded, input) do
          {:ok, result} -> {:ok, inspect(result)}
          other -> {:error, inspect(other)}
        end
    end
  end
end
