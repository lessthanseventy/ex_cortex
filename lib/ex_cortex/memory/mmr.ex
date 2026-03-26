defmodule ExCortex.Memory.MMR do
  @moduledoc """
  Maximal Marginal Relevance — reranks candidates to balance
  relevance to the query with diversity among selected results.
  """

  @default_lambda 0.7

  @doc """
  Rerank candidates using MMR.

  Each candidate must have an `:embedding` field (list of floats).
  Returns up to `limit` candidates reranked for relevance + diversity.

  Options:
    - `:limit` — max results (default 10)
    - `:lambda` — relevance vs diversity tradeoff, 0.0-1.0 (default 0.7)
  """
  def rerank(query, candidates, opts \\ [])
  def rerank(_query, [], _opts), do: []

  def rerank(query_embedding, candidates, opts) do
    limit = Keyword.get(opts, :limit, 10)
    lambda = Keyword.get(opts, :lambda, @default_lambda)

    scored =
      Enum.map(candidates, fn c ->
        Map.put(c, :_relevance, cosine_similarity(query_embedding, c.embedding))
      end)

    select_mmr(scored, query_embedding, lambda, limit, [])
  end

  defp select_mmr(_remaining, _query, _lambda, 0, selected), do: Enum.reverse(selected)
  defp select_mmr([], _query, _lambda, _limit, selected), do: Enum.reverse(selected)

  defp select_mmr(remaining, query, lambda, limit, selected) do
    best =
      Enum.max_by(remaining, fn candidate ->
        relevance = candidate._relevance

        max_sim =
          case selected do
            [] ->
              0.0

            _ ->
              selected
              |> Enum.map(&cosine_similarity(candidate.embedding, &1.embedding))
              |> Enum.max()
          end

        lambda * relevance - (1 - lambda) * max_sim
      end)

    remaining = Enum.reject(remaining, &(&1.id == best.id))
    select_mmr(remaining, query, lambda, limit - 1, [best | selected])
  end

  @doc "Cosine similarity between two vectors (lists of floats)."
  def cosine_similarity(a, b) when is_list(a) and is_list(b) do
    t_a = Nx.tensor(a, type: :f32)
    t_b = Nx.tensor(b, type: :f32)

    dot = t_a |> Nx.dot(t_b) |> Nx.to_number()
    norm_a = t_a |> Nx.LinAlg.norm() |> Nx.to_number()
    norm_b = t_b |> Nx.LinAlg.norm() |> Nx.to_number()

    denom = norm_a * norm_b

    if denom == 0.0 do
      0.0
    else
      dot / denom
    end
  end
end
