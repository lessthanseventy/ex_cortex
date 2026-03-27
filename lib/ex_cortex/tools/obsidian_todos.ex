defmodule ExCortex.Tools.ObsidianListTodos do
  @moduledoc "Tool: list open todos from Obsidian daily note."
  alias ExCortex.Tools.ObsidianTodos

  def req_llm_tool, do: ObsidianTodos.list_tool()
  defdelegate call(params), to: ObsidianTodos, as: :list_todos
end

defmodule ExCortex.Tools.ObsidianToggleTodo do
  @moduledoc "Tool: toggle a todo done/undone in Obsidian daily note."
  alias ExCortex.Tools.ObsidianTodos

  def req_llm_tool, do: ObsidianTodos.toggle_tool()
  defdelegate call(params), to: ObsidianTodos, as: :toggle_todo
end

defmodule ExCortex.Tools.ObsidianAddTodo do
  @moduledoc "Tool: add a new todo to Obsidian daily note."
  alias ExCortex.Tools.ObsidianTodos

  def req_llm_tool, do: ObsidianTodos.add_tool()
  defdelegate call(params), to: ObsidianTodos, as: :add_todo
end

defmodule ExCortex.Tools.ObsidianTodos do
  @moduledoc """
  Tools for managing todos in Obsidian daily notes.

  Reads/writes directly to the vault filesystem since obsidian-cli
  doesn't have checkbox-level operations.
  """

  alias ExCortex.Settings

  # ---------------------------------------------------------------------------
  # List Todos
  # ---------------------------------------------------------------------------

  def list_tool do
    ReqLLM.Tool.new!(
      name: "obsidian_list_todos",
      description:
        "List open (unchecked) todos from today's daily note in Obsidian. " <>
          "Returns todos grouped by section. Use date parameter for a different day.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "date" => %{
            "type" => "string",
            "description" => "Date in YYYY-MM-DD format. Defaults to today."
          }
        }
      },
      callback: &list_todos/1
    )
  end

  def list_todos(params) do
    date = Map.get(params, "date", resolve_today())

    case read_daily_note(date) do
      {:ok, content} ->
        todos = parse_todos(content, :open)

        if todos == [] do
          {:ok, "No open todos for #{date}."}
        else
          formatted = Enum.map_join(todos, "\n", &format_todo_section/1)

          {:ok, "Open todos for #{date}:\n\n#{formatted}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Toggle Todo (check/uncheck)
  # ---------------------------------------------------------------------------

  def toggle_tool do
    ReqLLM.Tool.new!(
      name: "obsidian_toggle_todo",
      description:
        "Mark a todo as done or undone in today's Obsidian daily note. " <>
          "Use obsidian_list_todos first to get line numbers, then pass the line number here. " <>
          "Or pass the todo text to match.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "line" => %{
            "type" => "integer",
            "description" => "Line number of the todo to toggle (from obsidian_list_todos)"
          },
          "text" => %{
            "type" => "string",
            "description" => "Text of the todo to toggle (fuzzy match). Used if line is not provided."
          },
          "date" => %{
            "type" => "string",
            "description" => "Date in YYYY-MM-DD format. Defaults to today."
          },
          "done" => %{
            "type" => "boolean",
            "description" => "true to mark done, false to mark undone. Defaults to true."
          }
        }
      },
      callback: &toggle_todo/1
    )
  end

  def toggle_todo(params) do
    date = Map.get(params, "date", resolve_today())
    done = Map.get(params, "done", true)
    {from, to} = todo_markers(done)

    case read_daily_note(date) do
      {:ok, content} ->
        lines = String.split(content, "\n")

        target_line =
          cond do
            params["line"] -> params["line"] - 1
            params["text"] -> find_todo_line(lines, params["text"], from)
            true -> nil
          end

        if is_nil(target_line) or target_line < 0 or target_line >= length(lines) do
          {:error, "Could not find the todo to toggle."}
        else
          apply_line_toggle(lines, target_line, from, to, done, date)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Add Todo
  # ---------------------------------------------------------------------------

  def add_tool do
    ReqLLM.Tool.new!(
      name: "obsidian_add_todo",
      description:
        "Add a new todo to today's Obsidian daily note. " <>
          "Adds it to the [!todo] 'what's happening' section by default. " <>
          "Use section='example' for the daily recurring checklist.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "text" => %{
            "type" => "string",
            "description" => "The todo text (without the checkbox — it's added automatically)"
          },
          "section" => %{
            "type" => "string",
            "description" =>
              "Callout type to add to: 'todo' for what's happening (default), 'example' for daily recurring. Matches [!type] in the note."
          },
          "date" => %{
            "type" => "string",
            "description" => "Date in YYYY-MM-DD format. Defaults to today."
          }
        },
        "required" => ["text"]
      },
      callback: &add_todo/1
    )
  end

  def add_todo(params) do
    date = Map.get(params, "date", resolve_today())
    text = params["text"]
    section = Map.get(params, "section", "todo")

    case read_daily_note(date) do
      {:ok, content} ->
        new_content = insert_todo(content, text, section)

        case write_daily_note(date, new_content) do
          :ok -> {:ok, "Added todo: #{text}"}
          {:error, reason} -> {:error, "Failed to write: #{reason}"}
        end

      {:error, :not_found} ->
        # Create the note with just the todo
        new_content = "# #{format_date_header(date)}\n\n> [!todo] what's happening\n> - [ ] #{text}\n"

        case write_daily_note(date, new_content) do
          :ok -> {:ok, "Created daily note and added todo: #{text}"}
          {:error, reason} -> {:error, "Failed to create: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp format_section_header(nil), do: ""
  defp format_section_header(section), do: "**#{section}**\n"

  defp format_todo_section({section, items}) do
    format_section_header(section) <>
      Enum.map_join(items, "\n", fn {line_num, text} -> "  #{line_num}: - [ ] #{text}" end)
  end

  defp todo_markers(true), do: {"- [ ]", "- [x]"}
  defp todo_markers(false), do: {"- [x]", "- [ ]"}

  defp todo_action(true), do: "completed"
  defp todo_action(false), do: "reopened"

  defp todo_state(true), do: "open"
  defp todo_state(false), do: "completed"

  defp apply_line_toggle(lines, target_line, from, to, done, date) do
    line = Enum.at(lines, target_line)

    if String.contains?(line, from) do
      new_line = String.replace(line, from, to, global: false)
      new_lines = List.replace_at(lines, target_line, new_line)
      new_content = Enum.join(new_lines, "\n")

      case write_daily_note(date, new_content) do
        :ok ->
          todo_text = line |> String.replace(~r/.*- \[.\]\s*/, "") |> String.trim()
          {:ok, "Todo #{todo_action(done)}: #{todo_text}"}

        {:error, reason} ->
          {:error, "Failed to write: #{reason}"}
      end
    else
      {:error, "Line #{target_line + 1} is not a #{todo_state(done)} todo."}
    end
  end

  defp update_todo_acc(acc, section, line_num, text) do
    case List.keyfind(acc, section, 0) do
      nil -> acc ++ [{section, [{line_num, text}]}]
      {^section, items} -> List.keyreplace(acc, section, 0, {section, items ++ [{line_num, text}]})
    end
  end

  defp vault_path do
    Settings.get(:obsidian_vault_path) || Path.expand("~/notes/notes")
  end

  defp daily_note_path(date) do
    Path.join([vault_path(), "journal", "#{date}.md"])
  end

  # Resolve today's date, falling back to yesterday if today's note doesn't exist.
  # Handles UTC timezone rollover.
  defp resolve_today do
    today = Date.to_iso8601(Date.utc_today())
    yesterday = Date.to_iso8601(Date.add(Date.utc_today(), -1))

    cond do
      File.exists?(daily_note_path(today)) -> today
      File.exists?(daily_note_path(yesterday)) -> yesterday
      true -> today
    end
  end

  defp read_daily_note(date) do
    path = daily_note_path(date)

    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, "#{reason}"}
    end
  end

  defp write_daily_note(date, content) do
    path = daily_note_path(date)
    File.mkdir_p!(Path.dirname(path))

    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, "#{reason}"}
    end
  end

  defp parse_todos(content, filter) do
    pattern =
      case filter do
        :open -> ~r/- \[ \]/
        :done -> ~r/- \[x\]/
        :all -> ~r/- \[[ x]\]/
      end

    lines = String.split(content, "\n")
    current_section = nil

    {todos, _} =
      Enum.reduce(Enum.with_index(lines, 1), {[], current_section}, fn {line, line_num}, {acc, section} ->
        # Track section from callout headers
        section =
          case Regex.run(~r/>\s*\[!(\w+)\]\s*(.*)/, line) do
            [_, _type, title] -> String.trim(title)
            _ -> section
          end

        if Regex.match?(pattern, line) do
          text = line |> String.replace(~r/.*- \[[ x]\]\s*/, "") |> String.trim()
          {update_todo_acc(acc, section, line_num, text), section}
        else
          {acc, section}
        end
      end)

    todos
  end

  defp split_whats_happening(lines) do
    # Split into: lines before section, section lines, lines after section
    section_start =
      Enum.find_index(lines, &String.match?(&1, ~r/^##\s+what's happening/i))

    if is_nil(section_start) do
      {lines, [], []}
    else
      before = Enum.take(lines, section_start + 1)
      rest = Enum.drop(lines, section_start + 1)

      # Section ends at the next heading or callout header
      section_end =
        Enum.find_index(rest, fn line ->
          String.match?(line, ~r/^##\s/) or String.match?(line, ~r/^>\s*\[!/)
        end)

      if is_nil(section_end) do
        {before, rest, []}
      else
        {before, Enum.take(rest, section_end), Enum.drop(rest, section_end)}
      end
    end
  end

  defp find_todo_line(lines, search_text, checkbox_pattern) do
    search_lower = String.downcase(search_text)

    Enum.find_index(lines, fn line ->
      String.contains?(line, checkbox_pattern) and
        String.contains?(String.downcase(line), search_lower)
    end)
  end

  defp insert_todo(content, text, _target_section) do
    lines = String.split(content, "\n")

    # Find "## what's happening", collect the section, find insert point
    {before, section_lines, after_lines} = split_whats_happening(lines)

    # Find the last actual todo line (not blank lines or empty checkboxes)
    last_todo_idx =
      section_lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _} -> String.match?(line, ~r/^[> ]*- \[[ x]\] .+/) end)
      |> List.last()
      |> case do
        {_, idx} -> idx
        nil -> length(section_lines) - 1
      end

    # Insert right after the last todo
    {top, bottom} = Enum.split(section_lines, last_todo_idx + 1)
    new_section = top ++ ["- [ ] #{text}"] ++ bottom

    # Ensure blank line before next section
    new_section =
      case after_lines do
        [] ->
          new_section

        [next | _] ->
          if String.trim(next) != "" and List.last(new_section) != "" do
            new_section ++ [""]
          else
            new_section
          end
      end

    Enum.join(before ++ new_section ++ after_lines, "\n")
  end

  defp format_date_header(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> Calendar.strftime(date, "%A, %B %-d %Y")
      _ -> date_str
    end
  end
end
