defmodule ExCortex.ContextProviders.Obsidian do
  @moduledoc """
  Injects Obsidian vault content as prompt context.

  Automatically detects what to fetch based on the input question:
  - todo/task/checklist → searches for "- [ ]" in note bodies
  - journal/daily/today → reads today's daily note
  - other obsidian/note queries → content search by keywords

  Config options:
    "mode" - "auto" (default), "todos", "daily", "search", "list"
    "query" - explicit search query (for "search" mode)
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  alias ExCortex.Tools.ReadObsidian
  alias ExCortex.Tools.SearchObsidian
  alias ExCortex.Tools.SearchObsidianContent

  @triggers ~w(obsidian note notes vault todo todos task tasks checklist journal daily)
  @meta_triggers ~w(system structure organize gaps missing setup workflow template folder tag)

  @impl true
  def build(config, _thought, input) do
    mode = Map.get(config, "mode", "auto")

    case mode do
      "auto" -> auto_gather(input)
      "todos" -> gather_todos()
      "daily" -> gather_daily()
      "search" -> gather_search(Map.get(config, "query", ""))
      "list" -> gather_list()
      _ -> auto_gather(input)
    end
  end

  defp auto_gather(input) do
    q_lower = String.downcase(input)
    relevant? = Enum.any?(@triggers, &String.contains?(q_lower, &1))
    meta? = Enum.any?(@meta_triggers, &String.contains?(q_lower, &1))

    if relevant? or meta? do
      results =
        []
        |> maybe_gather_vault_overview(q_lower, meta?)
        |> maybe_gather_todos(q_lower)
        |> maybe_gather_daily(q_lower)
        |> maybe_gather_search(q_lower)

      if results == [] do
        ""
      else
        "## Obsidian Vault\n\n" <> Enum.join(results, "\n\n")
      end
    else
      ""
    end
  end

  defp maybe_gather_vault_overview(results, _q_lower, false), do: results

  defp maybe_gather_vault_overview(results, _q_lower, true) do
    parts = []

    # List all notes to show vault structure
    parts =
      case SearchObsidian.call(%{"query" => ""}) do
        {:ok, content} when content != "" -> parts ++ ["### Vault Structure\n#{content}"]
        _ -> parts
      end

    # Read the vault overview note if it exists
    parts =
      for path <- ["how-i-use-this-vault.md", "README.md"],
          reduce: parts do
        acc ->
          case ReadObsidian.call(%{"path" => path}) do
            {:ok, content} when content != "" -> acc ++ ["### #{path}\n#{content}"]
            _ -> acc
          end
      end

    results ++ parts
  end

  defp maybe_gather_todos(results, q_lower) do
    if String.contains?(q_lower, "todo") or String.contains?(q_lower, "task") or
         String.contains?(q_lower, "checklist") do
      case gather_todos() do
        "" -> results
        content -> results ++ [content]
      end
    else
      results
    end
  end

  defp maybe_gather_daily(results, q_lower) do
    if String.contains?(q_lower, "journal") or String.contains?(q_lower, "daily") or
         String.contains?(q_lower, "today") do
      case gather_daily() do
        "" -> results
        content -> results ++ [content]
      end
    else
      results
    end
  end

  defp maybe_gather_search(results, q_lower) do
    if results == [] do
      search_terms =
        q_lower
        |> String.replace(~r/\b(how|many|what|are|the|my|in|do|i|have|of|a|an|is)\b/, "")
        |> String.replace(~r/\b(obsidian|notes?|vault)\b/, "")
        |> String.trim()

      if search_terms == "" do
        case gather_list() do
          "" -> results
          content -> results ++ [content]
        end
      else
        case SearchObsidianContent.call(%{"query" => search_terms}) do
          {:ok, content} when content != "" -> results ++ ["### Obsidian Search: #{search_terms}\n#{content}"]
          _ -> results
        end
      end
    else
      results
    end
  end

  defp gather_todos do
    case SearchObsidianContent.call(%{"query" => "- [ ]"}) do
      {:ok, content} when content != "" -> "### Open Todos\n#{content}"
      _ -> ""
    end
  end

  defp gather_daily do
    today = Calendar.strftime(Date.utc_today(), "%Y-%m-%d")

    case ReadObsidian.call(%{"path" => "journal/#{today}.md"}) do
      {:ok, content} when content != "" -> "### Daily Note (#{today})\n#{content}"
      _ -> ""
    end
  end

  defp gather_list do
    case SearchObsidian.call(%{"query" => ""}) do
      {:ok, content} when content != "" -> "### All Notes\n#{content}"
      _ -> ""
    end
  end

  defp gather_search(query) do
    case SearchObsidianContent.call(%{"query" => query}) do
      {:ok, content} when content != "" -> "### Obsidian Search: #{query}\n#{content}"
      _ -> ""
    end
  end
end
