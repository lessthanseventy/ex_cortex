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
    date = Map.get(params, "date", Date.to_iso8601(Date.utc_today()))
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

    {new_lines, state} =
      Enum.reduce(lines, {[], :seeking}, fn line, {acc, state} ->
        case state do
          :seeking ->
            # Match callout headers like "> [!abstract] brain dump"
            if callout_matches?(line, target_lower) do
              {acc ++ [line], :in_section}
            else
              {acc ++ [line], :seeking}
            end

          :in_section ->
            if String.starts_with?(String.trim(line), ">") do
              {acc ++ [line], :in_section}
            else
              # End of callout — insert before this line
              new_line = "> #{content}"
              {acc ++ [new_line] ++ [line], :done}
            end

          :done ->
            {acc ++ [line], :done}
        end
      end)

    # If still in_section at EOF, append there
    new_lines =
      if state == :in_section do
        new_lines ++ ["> #{content}"]
      else
        new_lines
      end

    if state == :seeking do
      {:error, "Could not find section matching '#{target_section}' in the daily note."}
    else
      {:ok, Enum.join(new_lines, "\n")}
    end
  end

  defp callout_matches?(line, target_lower) do
    case Regex.run(~r/>\s*\[!\w+\]\s*(.*)/i, line) do
      [_, title] -> String.contains?(String.downcase(String.trim(title)), target_lower)
      _ -> false
    end
  end

  defp vault_path do
    Settings.get(:obsidian_vault_path) || Path.expand("~/notes/notes")
  end

  defp daily_note_path(date) do
    Path.join([vault_path(), "journal", "#{date}.md"])
  end
end
