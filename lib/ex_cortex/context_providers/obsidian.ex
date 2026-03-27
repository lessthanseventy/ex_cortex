defmodule ExCortex.ContextProviders.Obsidian do
  @moduledoc """
  Injects Obsidian vault content as prompt context.

  Automatically detects what to fetch based on the input question:
  - todo/task/checklist → searches for "- [ ]" in note bodies
  - journal/daily/today → reads today's daily note
  - other obsidian/note queries → content search by keywords

  Config options:
    "mode" - "auto" (default), "todos", "daily", "daily_range", "search", "list"
    "query" - explicit search query (for "search" mode)
    "time_range" - for daily_range: "today", "yesterday", "week", "month" (default "today")
    "sections" - for daily_range: list of callout section names, or ["all"] (default ["all"])
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  alias ExCortex.Tools.ReadObsidian
  alias ExCortex.Tools.SearchObsidian
  alias ExCortex.Tools.SearchObsidianContent

  @triggers ~w(obsidian note notes vault todo todos task tasks checklist journal daily)
  @meta_triggers ~w(system structure organize gaps missing setup workflow template folder tag)

  @doc """
  Extracts specific callout sections from Obsidian daily note content.

  Section names use underscores to match callout titles with spaces (case-insensitive).
  Passing `["all"]` returns the full content unchanged.

  ## Examples

      extract_sections(content, ["brain_dump"])       # just the brain dump callout
      extract_sections(content, ["brain_dump", "todo"]) # both sections
      extract_sections(content, ["all"])               # full content
  """
  def extract_sections(content, ["all"]), do: content

  def extract_sections(content, section_names) when is_list(section_names) do
    targets = Enum.map(section_names, &String.replace(&1, "_", " "))

    content
    |> String.split("\n")
    |> collect_sections(targets, nil, [], [])
    |> Enum.join("\n\n")
  end

  defp collect_sections([], _targets, _current, current_lines, acc) do
    finalize_section(current_lines, acc)
  end

  defp collect_sections([line | rest], targets, current, current_lines, acc) do
    case parse_section_header(line) do
      {:callout, title} ->
        acc = finalize_section(current_lines, acc)

        if title_matches?(title, targets) do
          collect_sections(rest, targets, {:collecting, :callout}, [], acc)
        else
          collect_sections(rest, targets, nil, [], acc)
        end

      {:heading, title} ->
        acc = finalize_section(current_lines, acc)

        if title_matches?(title, targets) do
          collect_sections(rest, targets, {:collecting, :heading}, [], acc)
        else
          collect_sections(rest, targets, nil, [], acc)
        end

      :not_section ->
        handle_not_section_line(line, rest, targets, current, current_lines, acc)
    end
  end

  defp handle_not_section_line(line, rest, targets, {:collecting, :callout}, current_lines, acc) do
    if String.starts_with?(line, ">") do
      stripped = line |> String.replace_prefix("> ", "") |> String.replace_prefix(">", "")
      collect_sections(rest, targets, {:collecting, :callout}, current_lines ++ [stripped], acc)
    else
      acc = finalize_section(current_lines, acc)
      collect_sections(rest, targets, nil, [], acc)
    end
  end

  defp handle_not_section_line(line, rest, targets, {:collecting, :heading}, current_lines, acc) do
    # Heading sections collect until next heading, callout, or horizontal rule
    if String.match?(line, ~r/^---\s*$/) do
      acc = finalize_section(current_lines, acc)
      collect_sections(rest, targets, nil, [], acc)
    else
      collect_sections(rest, targets, {:collecting, :heading}, current_lines ++ [line], acc)
    end
  end

  defp handle_not_section_line(_line, rest, targets, _current, current_lines, acc) do
    collect_sections(rest, targets, nil, current_lines, acc)
  end

  defp parse_section_header(line) do
    case Regex.run(~r/^>\s*\[!(\w+)\]\s+(.+)$/, line) do
      [_, _type, title] ->
        {:callout, String.trim(title)}

      _ ->
        case Regex.run(~r/^##\s+(.+)$/, line) do
          [_, title] -> {:heading, String.trim(title)}
          _ -> :not_section
        end
    end
  end

  defp title_matches?(title, targets) do
    # Normalize: lowercase, strip apostrophes/punctuation for fuzzy matching
    normalize = fn s -> s |> String.downcase() |> String.replace(~r/[''"]/, "") end
    lower = normalize.(title)
    Enum.any?(targets, &(normalize.(&1) == lower))
  end

  defp finalize_section([], acc), do: acc
  defp finalize_section(lines, acc), do: acc ++ [Enum.join(lines, "\n")]

  @doc """
  Returns a list of `Date` structs for the given time range keyword.

  - `"today"` → `[ExCortex.LocalDate.today()]`
  - `"yesterday"` → `[Date.add(ExCortex.LocalDate.today(), -1)]`
  - `"week"` → last 7 dates (oldest first)
  - `"month"` → last 30 dates (oldest first)
  - anything else → `[ExCortex.LocalDate.today()]`
  """
  def date_range_for("today"), do: [ExCortex.LocalDate.today()]
  def date_range_for("yesterday"), do: [Date.add(ExCortex.LocalDate.today(), -1)]
  def date_range_for("week"), do: date_list(6)
  def date_range_for("month"), do: date_list(29)
  def date_range_for(_), do: [ExCortex.LocalDate.today()]

  defp date_list(days_back) do
    today = ExCortex.LocalDate.today()
    Enum.map(days_back..0//-1, &Date.add(today, -&1))
  end

  @impl true
  def build(config, _thought, input) do
    mode = Map.get(config, "mode", "auto")

    case mode do
      "auto" ->
        auto_gather(input)

      "todos" ->
        gather_todos()

      "daily" ->
        gather_daily()

      "search" ->
        gather_search(Map.get(config, "query", ""))

      "daily_range" ->
        gather_daily_range(
          Map.get(config, "time_range", "today"),
          Map.get(config, "sections", ["all"])
        )

      "list" ->
        gather_list()

      _ ->
        auto_gather(input)
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
          case ReadObsidian.call(%{"title" => path}) do
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
      search_terms = extract_search_terms(q_lower)
      search_fallback(results, search_terms)
    else
      results
    end
  end

  defp extract_search_terms(q_lower) do
    q_lower
    |> String.replace(~r/\b(how|many|what|are|the|my|in|do|i|have|of|a|an|is)\b/, "")
    |> String.replace(~r/\b(obsidian|notes?|vault)\b/, "")
    |> String.trim()
  end

  defp search_fallback(results, "") do
    case gather_list() do
      "" -> results
      content -> results ++ [content]
    end
  end

  defp search_fallback(results, search_terms) do
    case SearchObsidianContent.call(%{"query" => search_terms}) do
      {:ok, content} when content != "" -> results ++ ["### Obsidian Search: #{search_terms}\n#{content}"]
      _ -> results
    end
  end

  defp gather_todos do
    case SearchObsidianContent.call(%{"query" => "- [ ]"}) do
      {:ok, content} when content != "" -> "### Open Todos\n#{content}"
      _ -> ""
    end
  end

  defp gather_daily do
    today = Calendar.strftime(ExCortex.LocalDate.today(), "%Y-%m-%d")

    case ReadObsidian.call(%{"title" => "journal/#{today}.md"}) do
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

  defp gather_daily_range(time_range, sections) do
    dates = date_range_for(time_range)
    results = Enum.flat_map(dates, &fetch_daily_note(&1, sections))

    if results == [],
      do: "",
      else: "## Daily Notes (#{time_range})\n\n" <> Enum.join(results, "\n\n---\n\n")
  end

  defp fetch_daily_note(date, sections) do
    date_str = Calendar.strftime(date, "%Y-%m-%d")

    case ReadObsidian.call(%{"title" => "journal/#{date_str}.md"}) do
      {:ok, content} when content != "" ->
        filtered = extract_sections(content, sections)
        if filtered == "", do: [], else: ["### #{date_str}\n#{filtered}"]

      _ ->
        []
    end
  end

  defp gather_search(query) do
    case SearchObsidianContent.call(%{"query" => query}) do
      {:ok, content} when content != "" -> "### Obsidian Search: #{query}\n#{content}"
      _ -> ""
    end
  end
end
