defmodule ExCalibur.Lore do
  @moduledoc false
  import Ecto.Query

  alias ExCalibur.Lore.LoreEntry
  alias ExCalibur.Repo

  def list_entries(opts \\ []) do
    tags = Keyword.get(opts, :tags, [])
    quest_id = Keyword.get(opts, :quest_id)
    sort = Keyword.get(opts, :sort, "newest")

    query =
      from(e in LoreEntry)
      |> filter_tags(tags)
      |> filter_quest(quest_id)
      |> apply_sort(sort)

    Repo.all(query)
  end

  def get_entry!(id), do: Repo.get!(LoreEntry, id)

  def create_entry(attrs) do
    %LoreEntry{} |> LoreEntry.changeset(attrs) |> Repo.insert()
  end

  def update_entry(%LoreEntry{} = entry, attrs) do
    entry |> LoreEntry.changeset(attrs) |> Repo.update()
  end

  def delete_entry(%LoreEntry{} = entry), do: Repo.delete(entry)

  @doc """
  Used by artifact quest runs. Appends or replaces based on quest write_mode.
  - "append": always creates a new entry
  - "replace": overwrites the existing quest-owned entry (never overwrites source: "manual")
  - "both": replaces the pinned summary entry AND appends a dated log entry
  """
  def write_artifact(quest, attrs) do
    case quest.write_mode do
      "replace" ->
        replace_or_create(quest, attrs)

      "both" ->
        replace_or_create(quest, attrs)
        date = Calendar.strftime(Date.utc_today(), "%Y-%m-%d")
        log_template = quest.log_title_template || "#{quest.name || "Entry"} — Log — {date}"
        log_title = String.replace(log_template, "{date}", date)
        create_entry(Map.merge(attrs, %{quest_id: quest.id, title: log_title}))

      _ ->
        create_entry(Map.put(attrs, :quest_id, quest.id))
    end
  end

  defp replace_or_create(quest, attrs) do
    case Repo.one(
           from e in LoreEntry,
             where: e.quest_id == ^quest.id and e.source == "quest",
             limit: 1
         ) do
      nil -> create_entry(Map.put(attrs, :quest_id, quest.id))
      existing -> update_entry(existing, attrs)
    end
  end

  defp filter_tags(query, []), do: query

  defp filter_tags(query, tags) do
    from e in query, where: fragment("? && ?", e.tags, ^tags)
  end

  defp filter_quest(query, nil), do: query

  defp filter_quest(query, quest_id) do
    from e in query, where: e.quest_id == ^quest_id
  end

  defp apply_sort(query, "importance") do
    from e in query, order_by: [desc_nulls_last: e.importance, desc: e.inserted_at]
  end

  defp apply_sort(query, _newest) do
    from e in query, order_by: [desc: e.inserted_at]
  end
end
