defmodule ExCortex.Signals.TodoSync do
  @moduledoc """
  Syncs Obsidian daily note todos to a pinned checklist signal card on the Cortex.

  Reads today's daily note, parses todos from all callout sections,
  and upserts a pinned checklist card. Checking a todo on the dashboard
  toggles it in Obsidian via the action_handler.
  """

  alias ExCortex.Signals

  @pin_slug "daily-todos"

  def sync do
    today = ExCortex.LocalDate.today()

    {date, content} =
      case File.read(daily_note_path(Date.to_iso8601(today))) do
        {:ok, c} -> {today, c}
        _ -> {today, nil}
      end

    if content do
      items = parse_whats_happening(content)
      brain_dump = parse_section_bullets(content, ~r/^>\s*\[!abstract\]\s*brain dump/i)
      what_happened = parse_heading_bullets(content, ~r/^##\s+what happened/i)

      # Safety: never overwrite with empty data — skip if nothing was parsed
      if items != [] or brain_dump != [] or what_happened != [] do
        post_daily_card(items, brain_dump, what_happened, date)
      else
        :ok
      end
    else
      :ok
    end
  end

  # Parse todos from the "## what's happening" section of the daily note.
  # Handles both bare `- [ ]` items and callout-prefixed `> - [ ]` items.
  defp parse_whats_happening(content) do
    content
    |> String.split("\n")
    |> Enum.reduce({[], false}, &accumulate_whats_happening/2)
    |> elem(0)
  end

  defp accumulate_whats_happening(line, {items, in_section}) do
    cond do
      String.match?(line, ~r/^##\s+what's happening/i) -> {items, true}
      in_section -> accumulate_in_section(items, line, in_section)
      true -> {items, in_section}
    end
  end

  defp accumulate_in_section(items, line, in_section) do
    cond do
      String.match?(line, ~r/^##\s/) -> {items, false}
      String.match?(line, ~r/^>\s*\[!(?!todo)/) -> {items, false}
      String.match?(line, ~r/- \[ \]/) -> accumulate_todo(items, line, ~r/.*- \[ \]\s*/, false)
      String.match?(line, ~r/- \[x\]/) -> accumulate_todo(items, line, ~r/.*- \[x\]\s*/, true)
      true -> {items, in_section}
    end
  end

  # Parse bullet items from a callout section (brain dump, stuff that came up, etc.)
  defp parse_section_bullets(content, section_regex) do
    content
    |> String.split("\n")
    |> Enum.reduce({[], false, false}, fn line, acc -> accumulate_section_bullet(line, acc, section_regex) end)
    |> elem(0)
  end

  defp accumulate_section_bullet(line, {items, in_callout, past_callout}, section_regex) do
    cond do
      not in_callout and not past_callout and Regex.match?(section_regex, line) -> {items, true, false}
      in_callout -> accumulate_in_callout(items, line)
      past_callout -> handle_past_callout_line(items, line)
      true -> {items, in_callout, past_callout}
    end
  end

  defp accumulate_in_callout(items, line) do
    if String.starts_with?(String.trim(line), ">") do
      {items, true, false}
    else
      left_callout_line(items, line)
    end
  end

  defp left_callout_line(items, line) do
    case parse_bullet(line) do
      nil -> {items, false, true}
      text -> {items ++ [text], false, true}
    end
  end

  # Parse bullet items from a heading section (## what happened, etc.)
  # Returns maps: %{"text" => "thing", "checked" => true/false}
  defp parse_heading_bullets(content, heading_regex) do
    content
    |> String.split("\n")
    |> Enum.reduce({[], false}, &accumulate_heading_bullet(&1, &2, heading_regex))
    |> elem(0)
  end

  defp accumulate_heading_bullet(line, {items, in_section}, heading_regex) do
    cond do
      Regex.match?(heading_regex, line) -> {items, true}
      in_section -> accumulate_in_section_heading(items, line)
      true -> {items, in_section}
    end
  end

  defp accumulate_in_section_heading(items, line) do
    cond do
      String.match?(line, ~r/^##\s/) -> {items, false}
      String.match?(line, ~r/^>\s*\[!/) -> {items, false}
      String.match?(line, ~r/^---\s*$/) -> {items, false}
      true -> accumulate_heading_item(items, String.trim(line))
    end
  end

  defp accumulate_todo(items, line, regex, checked) do
    text = line |> String.replace(regex, "") |> String.trim()
    if text == "", do: {items, true}, else: {items ++ [%{"text" => text, "checked" => checked}], true}
  end

  defp handle_past_callout_line(items, line) do
    cond do
      String.match?(line, ~r/^>\s*\[!/) ->
        {items, false, false}

      String.match?(line, ~r/^##\s/) ->
        {items, false, false}

      true ->
        case parse_bullet(line) do
          nil -> {items, false, true}
          text -> {items ++ [text], false, true}
        end
    end
  end

  defp accumulate_heading_item(items, trimmed) do
    cond do
      String.match?(trimmed, ~r/^-\s*\[x\]/i) ->
        text = trimmed |> String.replace(~r/^-\s*\[x\]\s*/i, "") |> String.trim()
        if text == "", do: {items, true}, else: {items ++ [%{"text" => text, "checked" => true}], true}

      String.match?(trimmed, ~r/^-\s*\[ \]/) ->
        text = trimmed |> String.replace(~r/^-\s*\[ \]\s*/, "") |> String.trim()
        if text == "", do: {items, true}, else: {items ++ [%{"text" => text, "checked" => false}], true}

      String.match?(trimmed, ~r/^-\s+\S/) ->
        text = trimmed |> String.replace(~r/^-\s+/, "") |> String.trim()
        if text == "", do: {items, true}, else: {items ++ [%{"text" => text, "checked" => false}], true}

      true ->
        {items, true}
    end
  end

  defp parse_bullet(line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "-" or trimmed == "- " -> nil
      String.starts_with?(trimmed, "- ") -> String.trim_leading(trimmed, "- ")
      true -> nil
    end
  end

  defp daily_note_path(date) do
    vault_path = ExCortex.Settings.get(:obsidian_vault_path) || Path.expand("~/notes/notes")
    Path.join([vault_path, "journal", "#{date}.md"])
  end

  defp post_daily_card(items, brain_dump, what_happened, date) do
    label = Calendar.strftime(date, "%B %-d")

    Signals.post_signal(%{
      type: "checklist",
      title: "Today — #{label}",
      body: "",
      tags: ["todos", "obsidian", "daily"],
      source: "todo_sync",
      pin_slug: @pin_slug,
      pinned: true,
      pin_order: -1,
      metadata: %{
        "items" => items,
        "brain_dump" => brain_dump,
        "what_happened" => what_happened,
        "action_handler" => %{
          "toggle" => %{
            "tool" => "obsidian_toggle_todo",
            "args_template" => %{"text" => "{item.text}"}
          },
          "add" => %{
            "tool" => "obsidian_add_todo",
            "args_template" => %{"text" => "{input}"}
          },
          "brain_dump" => %{
            "tool" => "daily_note_write",
            "args_template" => %{"content" => "{input}", "section" => "brain dump"}
          },
          "what_happened" => %{
            "tool" => "daily_note_write",
            "args_template" => %{"content" => "[x] {input}", "section" => "what happened"}
          }
        }
      }
    })
  end
end
