defmodule ExCalibur.Agent.Consensus do
  @moduledoc """
  Consensus engine. Computes per-role consensus and cross-role decisions
  using pluggable strategies and action conflict topology.
  """

  def role_consensus(verdicts) do
    role = hd(verdicts).role
    active = Enum.reject(verdicts, &(&1.action == :abstain))

    if length(active) < 2 do
      %{
        role: role,
        decision: :inconclusive,
        confidence: 0.0,
        vote_count: vote_counts(verdicts),
        reasoning: "Insufficient active verdicts (#{length(active)}/#{length(verdicts)})"
      }
    else
      counts = vote_counts(active)
      {winner_action, _} = Enum.max_by(counts, fn {_k, v} -> v end)
      winners = Enum.filter(active, &(&1.action == winner_action))
      avg_conf = Enum.sum(Enum.map(active, & &1.confidence)) / length(active)

      %{
        role: role,
        decision: winner_action,
        confidence: avg_conf,
        vote_count: counts,
        reasoning: Enum.map_join(winners, "; ", & &1.reasoning)
      }
    end
  end

  def cross_role_decision(role_results, strategy) do
    avg_conf = Enum.sum(Enum.map(role_results, & &1.confidence)) / max(length(role_results), 1)

    case strategy do
      :majority -> majority_decision(role_results, avg_conf)
      :unanimous -> unanimous_decision(role_results, avg_conf)
      :highest_confidence -> highest_confidence_decision(role_results, [])
      {:role_veto, opts} -> role_veto_decision(role_results, avg_conf, opts)
      {:highest_confidence, opts} -> highest_confidence_decision(role_results, opts)
      {:weighted, opts} -> weighted_decision(role_results, opts)
      {:quorum, opts} -> quorum_decision(role_results, avg_conf, opts)
    end
  end

  defp majority_decision(role_results, avg_conf) do
    decisions = Enum.map(role_results, & &1.decision)
    counts = Enum.frequencies(decisions)
    active_decisions = Map.delete(counts, :inconclusive)

    cond do
      map_size(active_decisions) == 0 ->
        {:reject, 0.0}

      map_size(active_decisions) == 1 ->
        {action, _} = Enum.at(active_decisions, 0)
        {action, avg_conf}

      true ->
        {top_action, top_count} = Enum.max_by(active_decisions, fn {_k, v} -> v end)
        second_count = active_decisions |> Map.delete(top_action) |> Map.values() |> Enum.max(fn -> 0 end)

        if top_count > second_count, do: {top_action, avg_conf}, else: {:escalate, avg_conf}
    end
  end

  defp unanimous_decision(role_results, avg_conf) do
    active = Enum.reject(role_results, &(&1.decision == :inconclusive))
    decisions = active |> Enum.map(& &1.decision) |> Enum.uniq()

    case decisions do
      [single] -> {single, avg_conf}
      _ -> {:escalate, avg_conf}
    end
  end

  defp role_veto_decision(role_results, avg_conf, opts) do
    veto_roles = Keyword.fetch!(opts, :veto_roles)
    veto_rejects = Enum.filter(role_results, &(&1.role in veto_roles and &1.decision == :reject))
    if veto_rejects == [], do: majority_decision(role_results, avg_conf), else: {:reject, hd(veto_rejects).confidence}
  end

  defp highest_confidence_decision(role_results, opts) do
    min_conf = Keyword.get(opts, :min_confidence, 0.5)
    active = Enum.reject(role_results, &(&1.decision == :inconclusive))

    case active do
      [] ->
        {:reject, 0.0}

      _ ->
        winner = Enum.max_by(active, & &1.confidence)
        if winner.confidence >= min_conf, do: {winner.decision, winner.confidence}, else: {:escalate, winner.confidence}
    end
  end

  defp weighted_decision(role_results, opts) do
    weights = Keyword.fetch!(opts, :weights)

    scored =
      role_results
      |> Enum.reject(&(&1.decision == :inconclusive))
      |> Enum.group_by(& &1.decision)
      |> Enum.map(fn {action, results} ->
        score = Enum.sum(Enum.map(results, fn r -> Map.get(weights, r.role, 1.0) * r.confidence end))
        {action, score}
      end)

    case scored do
      [] ->
        {:reject, 0.0}

      _ ->
        {action, score} = Enum.max_by(scored, fn {_a, s} -> s end)
        {action, min(score, 1.0)}
    end
  end

  defp quorum_decision(role_results, avg_conf, opts) do
    min_quorum = Keyword.fetch!(opts, :min_quorum)
    active = Enum.reject(role_results, &(&1.decision == :inconclusive))
    if length(active) >= min_quorum, do: majority_decision(active, avg_conf), else: {:escalate, avg_conf}
  end

  defp vote_counts(verdicts), do: Enum.frequencies_by(verdicts, & &1.action)
end
