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
    case ObsidianTodos.list_todos(%{}) do
      {:ok, content} ->
        items = parse_items_from_output(content)
        post_checklist(items)

      {:error, :not_found} ->
        # No daily note today — clear the card
        post_checklist([])

      _ ->
        :ok
    end
  end

  defp parse_items_from_output(output) do
    output
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      cond do
        String.contains?(line, "- [ ]") ->
          text = line |> String.replace(~r/.*- \[ \]\s*/, "") |> String.trim()
          if text == "", do: [], else: [%{"text" => text, "checked" => false}]

        String.contains?(line, "- [x]") ->
          text = line |> String.replace(~r/.*- \[x\]\s*/, "") |> String.trim()
          if text == "", do: [], else: [%{"text" => text, "checked" => true}]

        true ->
          []
      end
    end)
  end

  defp post_checklist(items) do
    today = Calendar.strftime(Date.utc_today(), "%B %-d")

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
