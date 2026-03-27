defmodule ExCortex.TrustScorer do
  @moduledoc """
  Records neuron trust scores based on verdict consistency.
  Decays on disagreement (×0.97), boosts on agreement (×1.005, capped at 1.0).
  Scores influence consensus weighting via get_score/1.
  """

  import Ecto.Query

  alias ExCortex.Neurons.TrustScore
  alias ExCortex.Repo

  require Logger

  @decay_factor 0.97
  @boost_factor 1.005
  @max_score 1.0

  @doc "Asynchronously update scores for all neurons in a run."
  def record_run(steps) do
    Task.start(fn -> Enum.each(steps, &process_step_results/1) end)
  end

  defp process_step_results(step) do
    Enum.each(step.results || [], &update_trust(&1, step.verdict))
  end

  defp update_trust(result, step_verdict) do
    neuron_name = result[:neuron] || result.neuron

    if neuron_name do
      if result.verdict == step_verdict do
        boost(neuron_name)
      else
        decay(neuron_name)
      end
    end
  end

  @doc "Get a neuron's trust score. Returns 1.0 (default) if not tracked."
  def get_score(neuron_name) do
    case Repo.get_by(TrustScore, neuron_name: neuron_name) do
      nil -> @max_score
      %{score: score} -> score
    end
  end

  @doc "Decay a single neuron's trust score (disagreement with step verdict)."
  def decay(neuron_name) do
    case Repo.get_by(TrustScore, neuron_name: neuron_name) do
      nil ->
        Repo.insert(%TrustScore{
          neuron_name: neuron_name,
          score: @decay_factor,
          decay_count: 1
        })

      existing ->
        existing
        |> Ecto.Changeset.change(
          score: existing.score * @decay_factor,
          decay_count: existing.decay_count + 1
        )
        |> Repo.update()
    end
  end

  @doc "Boost a single neuron's trust score (agreement with step verdict)."
  def boost(neuron_name) do
    case Repo.get_by(TrustScore, neuron_name: neuron_name) do
      nil ->
        :ok

      existing ->
        new_score = min(existing.score * @boost_factor, @max_score)

        existing
        |> Ecto.Changeset.change(score: new_score)
        |> Repo.update()
    end
  end

  @doc "List all trust scores, ordered by score ascending (least trusted first)."
  def list_scores do
    Repo.all(from s in TrustScore, order_by: [asc: s.score])
  end
end
