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
    # Use local date, not UTC — daily notes follow the user's timezone
    today = Date.utc_today()
    yesterday = Date.add(today, -1)
    # Try today first, then yesterday (handles UTC rollover)

    {date, content} =
      case File.read(daily_note_path(Date.to_iso8601(today))) do
        {:ok, c} ->
          {today, c}

        _ ->
          case File.read(daily_note_path(Date.to_iso8601(yesterday))) do
            {:ok, c} -> {yesterday, c}
            _ -> {today, nil}
          end
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
    |> Enum.reduce({[], false}, fn line, {items, in_section} ->
      cond do
        # Start of our section
        String.match?(line, ~r/^##\s+what's happening/i) ->
          {items, true}

        # Next heading — stop
        in_section and String.match?(line, ~r/^##\s/) ->
          {items, false}

        # Next callout header that isn't a todo continuation — stop
        in_section and String.match?(line, ~r/^>\s*\[!(?!todo)/) ->
          {items, false}

        # Open todo (bare or callout-prefixed)
        in_section and String.match?(line, ~r/- \[ \]/) ->
          text = line |> String.replace(~r/.*- \[ \]\s*/, "") |> String.trim()
          if text == "", do: {items, true}, else: {items ++ [%{"text" => text, "checked" => false}], true}

        # Done todo
        in_section and String.match?(line, ~r/- \[x\]/) ->
          text = line |> String.replace(~r/.*- \[x\]\s*/, "") |> String.trim()
          if text == "", do: {items, true}, else: {items ++ [%{"text" => text, "checked" => true}], true}

        true ->
          {items, in_section}
      end
    end)
    |> elem(0)
  end

  # Parse bullet items from a callout section (brain dump, stuff that came up, etc.)
  defp parse_section_bullets(content, section_regex) do
    content
    |> String.split("\n")
    |> Enum.reduce({[], false, false}, fn line, {items, in_callout, past_callout} ->
      cond do
        # Found the callout header
        not in_callout and not past_callout and Regex.match?(section_regex, line) ->
          {items, true, false}

        # Still inside the callout (> prefixed lines) — skip
        in_callout and String.starts_with?(String.trim(line), ">") ->
          {items, true, false}

        # Just left the callout — now in the bullet area
        in_callout and not String.starts_with?(String.trim(line), ">") ->
          case parse_bullet(line) do
            nil -> {items, false, true}
            text -> {items ++ [text], false, true}
          end

        # In the post-callout area, collecting bullets
        past_callout ->
          cond do
            String.match?(line, ~r/^>\s*\[!/) ->
              {items, false, false}

            String.match?(line, ~r/^##\s/) ->
              {items, false, false}

            true ->
              case parse_bullet(line) do
                nil -> {items, false, past_callout}
                text -> {items ++ [text], false, true}
              end
          end

        true ->
          {items, in_callout, past_callout}
      end
    end)
    |> elem(0)
  end

  # Parse bullet items from a heading section (## what happened, etc.)
  # Strips checkbox syntax: "- [x] did a thing" → "did a thing"
  defp parse_heading_bullets(content, heading_regex) do
    content
    |> String.split("\n")
    |> Enum.reduce({[], false}, fn line, {items, in_section} ->
      cond do
        Regex.match?(heading_regex, line) ->
          {items, true}

        in_section and String.match?(line, ~r/^##\s/) ->
          {items, false}

        in_section and String.match?(line, ~r/^>\s*\[!/) ->
          {items, false}

        in_section and String.match?(line, ~r/^---\s*$/) ->
          {items, false}

        in_section ->
          text =
            line
            |> String.trim()
            |> String.replace(~r/^-\s*\[.\]\s*/, "")
            |> String.replace(~r/^-\s*/, "")
            |> String.trim()

          if text == "", do: {items, in_section}, else: {items ++ [text], true}

        true ->
          {items, in_section}
      end
    end)
    |> elem(0)
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
