defmodule ExCortex.Tools.DailyNoteWrite do
  @moduledoc "Tool: write content into a specific section of today's Obsidian daily note."

  alias ExCortex.Settings

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "daily_note_write",
      description:
        "Write content into a specific section of today's Obsidian daily note. " <>
          "Sections are Obsidian callout blocks like 'brain dump', 'todo', 'stuff that came up'. " <>
          "Content is appended inside the matching > [!type] section as a new > prefixed line. " <>
          "Use section='brain dump' for thoughts, 'todo' for tasks (use obsidian_add_todo instead for checkboxes), " <>
          "'stuff that came up' for things to revisit later.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "content" => %{
            "type" => "string",
            "description" => "The content to write (without the > prefix — it's added automatically)"
          },
          "section" => %{
            "type" => "string",
            "description" =>
              "The callout section title to write into (e.g. 'brain dump', 'todo', 'stuff that came up'). Case-insensitive partial match."
          },
          "date" => %{
            "type" => "string",
            "description" => "Date in YYYY-MM-DD format. Defaults to today."
          }
        },
        "required" => ["content", "section"]
      },
      callback: &call/1
    )
  end

  def call(%{"content" => content, "section" => section} = params) do
    date = Map.get(params, "date", resolve_today())
    path = daily_note_path(date)

    case File.read(path) do
      {:ok, file_content} ->
        case insert_in_section(file_content, content, section) do
          {:ok, new_content} ->
            File.write!(path, new_content)
            {:ok, "Added to '#{section}' in daily note #{date}"}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :enoent} ->
        {:error, "No daily note for #{date}. Create one first."}

      {:error, reason} ->
        {:error, "#{reason}"}
    end
  end

  defp insert_in_section(file_content, content, target_section) do
    lines = String.split(file_content, "\n")
    target_lower = String.downcase(String.trim(target_section))

    # Find the callout header
    section_start = Enum.find_index(lines, &callout_matches?(&1, target_lower))

    if is_nil(section_start) do
      {:error, "Could not find section matching '#{target_section}' in the daily note."}
    else
      # Collect: callout lines (> prefixed), then post-callout lines until next section
      before = Enum.take(lines, section_start + 1)
      rest = Enum.drop(lines, section_start + 1)

      # Split rest into: callout body (> lines), then post-callout area, then next section
      {callout_lines, after_callout} =
        Enum.split_while(rest, &String.starts_with?(String.trim(&1), ">"))

      {section_lines, after_section} =
        Enum.split_while(after_callout, fn line ->
          not String.match?(line, ~r/^>\s*\[!/) and not String.match?(line, ~r/^##\s/)
        end)

      # Check for an empty placeholder bullet "- " to fill
      empty_idx =
        Enum.find_index(section_lines, fn line ->
          String.trim(line) == "-" or String.trim(line) == "- "
        end)

      new_section =
        if empty_idx do
          # Replace the first empty placeholder
          List.replace_at(section_lines, empty_idx, "- #{content}")
        else
          # Find last bullet and insert after it
          last_bullet_idx =
            section_lines
            |> Enum.with_index()
            |> Enum.filter(fn {line, _} -> String.match?(line, ~r/^- .+/) end)
            |> List.last()

          case last_bullet_idx do
            {_, idx} ->
              {top, bottom} = Enum.split(section_lines, idx + 1)
              top ++ ["- #{content}"] ++ bottom

            nil ->
              # No bullets yet — add one
              section_lines ++ ["- #{content}"]
          end
        end

      # Ensure blank line before next section
      new_section =
        case after_section do
          [next | _] when next != "" ->
            if List.last(new_section) == "", do: new_section, else: new_section ++ [""]

          _ ->
            new_section
        end

      {:ok, Enum.join(before ++ callout_lines ++ new_section ++ after_section, "\n")}
    end
  end

  defp callout_matches?(line, target_lower) do
    case Regex.run(~r/>\s*\[!\w+\]\s*(.*)/i, line) do
      [_, title] -> String.contains?(String.downcase(String.trim(title)), target_lower)
      _ -> false
    end
  end

  defp resolve_today do
    today = Date.to_iso8601(Date.utc_today())
    yesterday = Date.to_iso8601(Date.add(Date.utc_today(), -1))

    cond do
      File.exists?(daily_note_path(today)) -> today
      File.exists?(daily_note_path(yesterday)) -> yesterday
      true -> today
    end
  end

  defp vault_path do
    Settings.get(:obsidian_vault_path) || Path.expand("~/notes/notes")
  end

  defp daily_note_path(date) do
    Path.join([vault_path(), "journal", "#{date}.md"])
  end
end
