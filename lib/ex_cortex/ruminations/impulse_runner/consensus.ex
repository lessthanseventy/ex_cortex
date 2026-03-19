defmodule ExCortex.Ruminations.ImpulseRunner.Consensus do
  @moduledoc false

  @verdict_order %{"fail" => 0, "warn" => 1, "abstain" => 2, "pass" => 3}

  def parse_verdict(text) do
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

  def aggregate([], _, _), do: "abstain"

  def aggregate(results, "solo", _laterality) do
    results |> List.first() |> Map.get(:verdict, "abstain")
  end

  # Right hemisphere (divergent): if any neuron has high confidence, their verdict
  # can pull the group — novel insights win over consensus.
  # Trust score weights the effective confidence: a low-trust neuron's "high confidence"
  # is discounted, so it's less likely to pull the group.
  def aggregate(results, "consensus", %{hemisphere: :right, confidence_threshold: threshold}) do
    verdicts = Enum.map(results, & &1.verdict)

    high_confidence =
      Enum.find(results, fn r ->
        effective_confidence(r) >= threshold
      end)

    cond do
      Enum.uniq(verdicts) == [hd(verdicts)] -> hd(verdicts)
      high_confidence -> high_confidence.verdict
      true -> best_verdict(verdicts)
    end
  end

  # Left hemisphere (systematic): unanimous or worst-case — conservative default.
  def aggregate(results, "consensus", _laterality) do
    verdicts = Enum.map(results, & &1.verdict)
    if Enum.uniq(verdicts) == [hd(verdicts)], do: hd(verdicts), else: worst_verdict(verdicts)
  end

  # Right hemisphere majority: lower bar — any non-abstain verdict with at least one vote wins.
  def aggregate(results, _majority, %{hemisphere: :right}) do
    verdicts = results |> Enum.map(& &1.verdict) |> Enum.reject(&(&1 == "abstain"))
    if verdicts == [], do: "abstain", else: best_verdict(verdicts)
  end

  def aggregate(results, _majority, _laterality) do
    verdicts = Enum.map(results, & &1.verdict)
    verdicts |> Enum.frequencies() |> Enum.max_by(fn {_, count} -> count end) |> elem(0)
  end

  @doc "Compute effective confidence: raw confidence × trust score."
  def effective_confidence(result) do
    raw = result[:confidence] || 0.0
    trust = ExCortex.TrustScorer.get_score(result[:neuron] || "")
    raw * trust
  end

  def worst_verdict(verdicts) do
    Enum.min_by(verdicts, &Map.get(@verdict_order, &1, 2))
  end

  def best_verdict(verdicts) do
    Enum.max_by(verdicts, &Map.get(@verdict_order, &1, 2))
  end
end
