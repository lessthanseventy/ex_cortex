defmodule ExCalibur.ContextProviders.Lore do
  @moduledoc """
  Injects lore entries as prompt context.
  Config: %{"type" => "lore", "tags" => ["a11y"], "limit" => 10, "sort" => "importance"}
  """

  @behaviour ExCalibur.ContextProviders.ContextProvider

  alias ExCalibur.Lore

  @impl true
  def build(config, _quest, _input) do
    tags = Map.get(config, "tags", [])
    limit = Map.get(config, "limit", 10)
    sort = Map.get(config, "sort", "newest")

    entries = Lore.list_entries(tags: tags, sort: sort) |> Enum.take(limit)

    if entries == [] do
      ""
    else
      lines =
        Enum.map(entries, fn entry ->
          importance = if entry.importance, do: " [importance: #{entry.importance}]", else: ""
          tags_str = if entry.tags != [], do: "\nTags: #{Enum.join(entry.tags, ", ")}", else: ""
          "### #{entry.title}#{importance}#{tags_str}\n#{entry.body}"
        end)

      String.trim("""
      ## Lore Context
      #{Enum.join(lines, "\n\n")}
      """)
    end
  end
end
