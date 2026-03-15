defmodule ExCortex.ContextProviders.Engrams do
  @moduledoc """
  Injects engrams as prompt context.

  Config options:
    "tags"  - filter by tags (required)
    "limit" - max entries (default 5)
    "sort"  - "newest" | "importance" | "top" (default "newest")

  sort: "top" blends the highest-importance entries with the most recent ones,
  so important historical signal never gets crowded out by low-quality noise,
  but fresh data still makes it in.
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  alias ExCortex.Memory

  # Total character budget for all memory context sent to a model.
  # High-importance entries (5) get extra budget via body_cap/1.
  @total_cap 6_000

  @impl true
  def build(config, _thought, _input) do
    tags = Map.get(config, "tags", [])
    limit = Map.get(config, "limit", 5)
    sort = Map.get(config, "sort", "newest")

    entries = select_entries(tags, sort, limit)

    if entries == [] do
      ""
    else
      lines = Enum.map(entries, &format_entry/1)

      output =
        String.trim("""
        ## Memory Context
        #{Enum.join(lines, "\n\n")}
        """)

      String.slice(output, 0, @total_cap)
    end
  end

  # "top" = most important entries + most recent entry, merged and deduplicated.
  # Gives important historical signal priority while keeping fresh data present.
  defp select_entries(tags, "top", limit) do
    half = max(1, div(limit, 2))
    by_importance = [tags: tags, sort: "importance"] |> Memory.list_engrams() |> Enum.take(half)
    by_recency = [tags: tags, sort: "newest"] |> Memory.list_engrams() |> Enum.take(half)

    (by_importance ++ by_recency)
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(limit)
  end

  defp select_entries(tags, sort, limit) do
    [tags: tags, sort: sort] |> Memory.list_engrams() |> Enum.take(limit)
  end

  # Higher-importance entries get more body budget so signal isn't truncated.
  defp body_cap(%{importance: 5}), do: 4_000
  defp body_cap(%{importance: n}) when is_integer(n) and n >= 4, do: 600
  defp body_cap(%{importance: n}) when is_integer(n) and n >= 2, do: 300
  defp body_cap(_), do: 150

  defp format_entry(entry) do
    importance = if entry.importance, do: " [importance: #{entry.importance}]", else: ""
    tags_str = if entry.tags == [], do: "", else: "\nTags: #{Enum.join(entry.tags, ", ")}"
    body = String.slice(entry.body || "", 0, body_cap(entry))
    "### #{entry.title}#{importance}#{tags_str}\n#{body}"
  end
end
