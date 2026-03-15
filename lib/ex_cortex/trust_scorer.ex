defmodule ExCortex.TrustScorer do
  @moduledoc """
  Records neuron trust scores based on verdict consistency.
  When a neuron's individual verdict contradicts the aggregated step verdict,
  their score decays by ×0.97.
  """

  import Ecto.Query

  alias ExCortex.Neurons.TrustScore
  alias ExCortex.Repo

  require Logger

  @decay_factor 0.97

  @doc "Asynchronously decay scores for neurons who contradicted their step's verdict."
  def record_run(steps) do
    Task.start(fn -> Enum.each(steps, &process_step_results/1) end)
  end

  defp process_step_results(step) do
    step_verdict = step.verdict

    Enum.each(step.results || [], fn result ->
      member_name = result[:neuron] || result.neuron
      if member_name && result.verdict != step_verdict, do: decay(member_name)
    end)
  end

  @doc "Decay a single neuron's trust score."
  def decay(member_name) do
    case Repo.get_by(TrustScore, member_name: member_name) do
      nil ->
        Repo.insert(%TrustScore{
          member_name: member_name,
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

  @doc "List all trust scores, ordered by score ascending (least trusted first)."
  def list_scores do
    Repo.all(from s in TrustScore, order_by: [asc: s.score])
  end
end
