defmodule ExCortex.Ruminations.ImpulseRunner.Reflect do
  @moduledoc false

  alias ExCortex.Ruminations.ImpulseRunner

  def do_reflect(thought, input_text, _tools, _threshold, _reflect_on, max_iter, iter) when iter >= max_iter do
    ImpulseRunner.run(thought.roster, input_text, ImpulseRunner.dangerous_tool_opts(thought))
  end

  def do_reflect(thought, input_text, tools, threshold, reflect_on, max_iter, iter) do
    result = ImpulseRunner.run(thought.roster, input_text, ImpulseRunner.dangerous_tool_opts(thought))

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

  def gather_reflect_context(tools, verdict) do
    memory_tool = Enum.find(tools, &(&1.name == "query_memory"))

    if memory_tool do
      gather_memory_context(memory_tool, verdict)
    else
      gather_tool_context(tools)
    end
  end

  def gather_memory_context(memory_tool, verdict) do
    case ReqLLM.Tool.execute(memory_tool, %{"tags" => [], "limit" => 3}) do
      {:ok, content} -> "Prior memory context (verdict was #{verdict}):\n#{content}"
      _ -> ""
    end
  end

  def gather_tool_context(tools) do
    tools
    |> Enum.map(&execute_tool_for_context/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  def execute_tool_for_context(tool) do
    case ReqLLM.Tool.execute(tool, %{}) do
      {:ok, result} -> to_string(result)
      _ -> ""
    end
  end
end
