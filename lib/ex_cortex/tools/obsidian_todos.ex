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
    date = Map.get(params, "date", Date.to_iso8601(Date.utc_today()))

    case read_daily_note(date) do
      {:ok, content} ->
        todos = parse_todos(content, :open)

        if todos == [] do
          {:ok, "No open todos for #{date}."}
        else
          formatted =
            Enum.map_join(todos, "\n", fn {section, items} ->
              header = if section, do: "**#{section}**\n", else: ""
              header <> Enum.map_join(items, "\n", fn {line_num, text} -> "  #{line_num}: - [ ] #{text}" end)
            end)

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
    date = Map.get(params, "date", Date.to_iso8601(Date.utc_today()))
    done = Map.get(params, "done", true)
    from = if done, do: "- [ ]", else: "- [x]"
    to = if done, do: "- [x]", else: "- [ ]"

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
          line = Enum.at(lines, target_line)

          if String.contains?(line, from) do
            new_line = String.replace(line, from, to, global: false)
            new_lines = List.replace_at(lines, target_line, new_line)
            new_content = Enum.join(new_lines, "\n")

            case write_daily_note(date, new_content) do
              :ok ->
                todo_text = line |> String.replace(~r/.*- \[.\]\s*/, "") |> String.trim()
                action = if done, do: "completed", else: "reopened"
                {:ok, "Todo #{action}: #{todo_text}"}

              {:error, reason} ->
                {:error, "Failed to write: #{reason}"}
            end
          else
            {:error, "Line #{target_line + 1} is not a #{if done, do: "open", else: "completed"} todo."}
          end
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
          "Adds it to the [!todo] section by default, or specify a section.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "text" => %{
            "type" => "string",
            "description" => "The todo text (without the checkbox — it's added automatically)"
          },
          "section" => %{
            "type" => "string",
            "description" => "Section to add to. Matches callout type like 'todo', 'example'. Default: 'todo'."
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
    date = Map.get(params, "date", Date.to_iso8601(Date.utc_today()))
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

  defp vault_path do
    Settings.get(:obsidian_vault_path) || Path.expand("~/notes/notes")
  end

  defp daily_note_path(date) do
    Path.join([vault_path(), "journal", "#{date}.md"])
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
          # Group by section
          updated =
            case List.keyfind(acc, section, 0) do
              nil -> acc ++ [{section, [{line_num, text}]}]
              {^section, items} -> List.keyreplace(acc, section, 0, {section, items ++ [{line_num, text}]})
            end

          {updated, section}
        else
          {acc, section}
        end
      end)

    todos
  end

  defp find_todo_line(lines, search_text, checkbox_pattern) do
    search_lower = String.downcase(search_text)

    Enum.find_index(lines, fn line ->
      String.contains?(line, checkbox_pattern) and
        String.contains?(String.downcase(line), search_lower)
    end)
  end

  defp insert_todo(content, text, target_section) do
    lines = String.split(content, "\n")
    target_lower = String.downcase(target_section)

    # Find the target callout section and insert after the last todo in it
    {new_lines, _inserted} =
      Enum.reduce(lines, {[], :seeking}, fn line, {acc, state} ->
        case state do
          :seeking ->
            if Regex.match?(~r/>\s*\[!#{Regex.escape(target_lower)}\]/i, line) do
              {acc ++ [line], :in_section}
            else
              {acc ++ [line], :seeking}
            end

          :in_section ->
            if String.starts_with?(String.trim(line), ">") do
              {acc ++ [line], :in_section}
            else
              # End of callout — insert the new todo before this line
              {acc ++ ["> - [ ] #{text}"] ++ [line], :done}
            end

          :done ->
            {acc ++ [line], :done}
        end
      end)

    # If we're still in_section at the end (section is last thing in file), append there
    _ = List.last(Tuple.to_list({new_lines, nil}))
    new_lines = if Enum.member?([:in_section], nil), do: new_lines ++ ["> - [ ] #{text}"], else: new_lines
    Enum.join(new_lines, "\n")
  end

  defp format_date_header(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> Calendar.strftime(date, "%A, %B %-d %Y")
      _ -> date_str
    end
  end
end
