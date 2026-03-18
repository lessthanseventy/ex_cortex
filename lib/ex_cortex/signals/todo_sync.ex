defmodule ExCortex.Signals.TodoSync do
  @moduledoc """
  Syncs Obsidian daily note todos to a pinned checklist signal card on the Cortex.

  Reads today's daily note, parses todos from all callout sections,
  and upserts a pinned checklist card. Checking a todo on the dashboard
  toggles it in Obsidian via the action_handler.
  """

  alias ExCortex.Signals
  alias ExCortex.Tools.ObsidianTodos

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
      post_checklist(items, date)
    else
      post_checklist([], today)
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

  defp daily_note_path(date) do
    vault_path = ExCortex.Settings.get(:obsidian_vault_path) || Path.expand("~/notes/notes")
    Path.join([vault_path, "journal", "#{date}.md"])
  end

  defp post_checklist(items, date) do
    today = Calendar.strftime(date, "%B %-d")

    Signals.post_signal(%{
      type: "checklist",
      title: "Today's Todos — #{today}",
      body: "",
      tags: ["todos", "obsidian", "daily"],
      source: "todo_sync",
      pin_slug: @pin_slug,
      pinned: true,
      pin_order: -1,
      metadata: %{
        "items" => items,
        "action_handler" => %{
          "toggle" => %{
            "tool" => "obsidian_toggle_todo",
            "args_template" => %{"text" => "{item.text}"}
          },
          "add" => %{
            "tool" => "obsidian_add_todo",
            "args_template" => %{"text" => "{input}"}
          }
        }
      }
    })
  end
end
