defmodule ExCortex.ContextProviders.Email do
  @moduledoc """
  Injects email search results as prompt context.

  Automatically detects email-related queries and builds appropriate
  notmuch search queries.

  Config options:
    "mode" - "auto" (default), "search"
    "query" - explicit notmuch query (for "search" mode)
    "limit" - max results (default 10)
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  @triggers ~w(email mail inbox message sent unread newsletter)

  @impl true
  def build(config, _thought, input) do
    mode = Map.get(config, "mode", "auto")
    limit = Map.get(config, "limit", "10")

    case mode do
      "auto" -> auto_gather(input, limit)
      "search" -> do_search(Map.get(config, "query", "tag:inbox"), limit)
      _ -> auto_gather(input, limit)
    end
  end

  defp auto_gather(input, limit) do
    q_lower = String.downcase(input)
    relevant? = Enum.any?(@triggers, &String.contains?(q_lower, &1))

    if relevant? do
      query = build_query(q_lower)
      do_search(query, limit)
    else
      ""
    end
  end

  defp build_query(q_lower) do
    # Strip common words to extract search terms
    search_terms =
      q_lower
      |> String.replace(
        ~r/\b(how|many|what|are|the|my|in|do|i|have|of|a|an|is|any|from|about|show|me|get)\b/,
        ""
      )
      |> String.replace(~r/\b(email|emails|mail|inbox|message|messages|unread)\b/, "")
      |> String.trim()

    cond do
      String.contains?(q_lower, "unread") -> "tag:unread"
      String.contains?(q_lower, "newsletter") -> "tag:newsletter OR folder:Newsletter"
      search_terms != "" -> search_terms
      true -> "tag:inbox date:7days.."
    end
  end

  defp do_search(query, limit) do
    case ExCortex.Tools.SearchEmail.call(%{"query" => query, "limit" => to_string(limit)}) do
      {:ok, content} when content != "" ->
        "## Email\n\n### Search: #{query}\n#{content}"

      _ ->
        ""
    end
  end
end
