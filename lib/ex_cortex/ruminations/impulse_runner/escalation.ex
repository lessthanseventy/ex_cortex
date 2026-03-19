defmodule ExCortex.Ruminations.ImpulseRunner.Escalation do
  @moduledoc false

  alias ExCortex.Ruminations.ImpulseRunner
  alias ExCortex.Ruminations.RosterResolver

  def try_escalate_rank(rank, thought, augmented, threshold, escalate_on) do
    neurons = RosterResolver.resolve(rank)

    if neurons == [] do
      {:cont, nil}
    else
      result = ImpulseRunner.run(thought.roster, augmented, ImpulseRunner.dangerous_tool_opts(thought))
      evaluate_escalate_result(result, threshold, escalate_on)
    end
  end

  def evaluate_escalate_result({:ok, %{verdict: v, steps: steps}} = ok, threshold, escalate_on) do
    avg_confidence = average_step_confidence(steps)
    satisfied = avg_confidence >= threshold and v not in escalate_on
    if satisfied, do: {:halt, ok}, else: {:cont, ok}
  end

  def evaluate_escalate_result(other, _threshold, _escalate_on), do: {:cont, other}

  def average_step_confidence(steps) do
    steps
    |> Enum.flat_map(& &1.results)
    |> Enum.map(&Map.get(&1, :confidence, 0.5))
    |> then(fn
      [] -> 0.5
      cs -> Enum.sum(cs) / length(cs)
    end)
  end
end
