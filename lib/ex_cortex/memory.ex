defmodule ExCortex.Memory do
  @moduledoc "Context for engrams (memories) with tiered loading."
  import Ecto.Query

  alias ExCortex.Memory.Engram
  alias ExCortex.Memory.RecallPath
  alias ExCortex.Repo

  def list_engrams(opts \\ []) do
    tags = Keyword.get(opts, :tags, [])
    quest_id = Keyword.get(opts, :thought_id)
    sort = Keyword.get(opts, :sort, "newest")

    query =
      from(e in Engram)
      |> filter_tags(tags)
      |> filter_quest(quest_id)
      |> apply_sort(sort)

    Repo.all(query)
  end

  def get_engram!(id), do: Repo.get!(Engram, id)

  def create_engram(attrs) do
    %Engram{} |> Engram.changeset(attrs) |> Repo.insert()
  end

  def update_engram(%Engram{} = engram, attrs) do
    engram |> Engram.changeset(attrs) |> Repo.update()
  end

  def delete_engram(%Engram{} = engram), do: Repo.delete(engram)

  @doc """
  Used by artifact daydreams. Appends or replaces based on thought write_mode.
  - "append": always creates a new entry
  - "replace": overwrites the existing thought-owned entry (never overwrites source: "manual")
  - "both": replaces the pinned summary entry AND appends a dated log entry
  """
  def write_artifact(thought, attrs) do
    if repetitive_content?(attrs[:body]) do
      require Logger

      Logger.warning("[Memory] Rejecting repetitive/garbled artifact for thought #{thought.id}")
      {:error, :repetitive_content}
    else
      result =
        case thought.write_mode do
          "replace" ->
            replace_or_create(thought, attrs)

          "both" ->
            replace_or_create(thought, attrs)
            date = Calendar.strftime(Date.utc_today(), "%Y-%m-%d")
            log_template = thought.log_title_template || "#{thought.name || "Entry"} — Log — {date}"
            log_title = String.replace(log_template, "{date}", date)
            create_engram(Map.merge(attrs, %{thought_id: thought.id, title: log_title}))

          _ ->
            create_engram(Map.put(attrs, :thought_id, thought.id))
        end

      with {:ok, entry} <- result, do: broadcast_and_sync(entry)

      result
    end
  end

  defp broadcast_and_sync(entry) do
    Phoenix.PubSub.broadcast(ExCortex.PubSub, "memory", {:lore_updated, entry.title})
    Phoenix.PubSub.broadcast(ExCortex.PubSub, "lore_triggers", {:lore_entry_created, entry})

    ExCortex.Obsidian.Sync.sync_lore_entry(entry)
  end

  defp replace_or_create(thought, attrs) do
    case Repo.one(
           from e in Engram,
             where: e.thought_id == ^thought.id and e.source == "thought",
             limit: 1
         ) do
      nil -> create_engram(Map.put(attrs, :thought_id, thought.id))
      existing -> update_engram(existing, attrs)
    end
  end

  # Detect LLM token-repetition loops (e.g. "and and and and and...")
  defp repetitive_content?(nil), do: false

  defp repetitive_content?(body) when is_binary(body) do
    Regex.match?(~r/\b(\w+)\b(?:[\s,]+\1){5,}/i, body)
  end

  # --- Tiered Query ---

  def query(search_term, opts \\ []) do
    tier = Keyword.get(opts, :tier, :L0)
    limit = Keyword.get(opts, :limit, 20)

    select_fields =
      case tier do
        :L0 -> [:id, :title, :impression, :tags, :importance, :category, :inserted_at]
        :L1 -> [:id, :title, :impression, :recall, :tags, :importance, :category, :inserted_at]
        :L2 -> [:id, :title, :impression, :recall, :body, :tags, :importance, :category, :inserted_at]
      end

    Repo.all(
      from(e in Engram,
        where: ilike(e.title, ^"%#{search_term}%") or ilike(e.impression, ^"%#{search_term}%") or ^search_term in e.tags,
        select: struct(e, ^select_fields),
        order_by: [desc: e.importance, desc: e.inserted_at],
        limit: ^limit
      )
    )
  end

  def load_recall(engram_id) do
    Repo.one(
      from(e in Engram,
        where: e.id == ^engram_id,
        select: struct(e, [:id, :title, :impression, :recall, :tags, :importance, :category])
      )
    )
  end

  def load_deep(engram_id) do
    Repo.get(Engram, engram_id)
  end

  # --- Recall Paths ---

  def log_recall(attrs) do
    %RecallPath{}
    |> RecallPath.changeset(attrs)
    |> Repo.insert()
  end

  def recall_paths_for_daydream(daydream_id) do
    Repo.all(
      from(rp in RecallPath,
        where: rp.daydream_id == ^daydream_id,
        join: e in Engram,
        on: e.id == rp.engram_id,
        select: %{recall_path: rp, engram_title: e.title},
        order_by: [asc: rp.step, asc: rp.inserted_at]
      )
    )
  end

  # --- Filters ---

  defp filter_tags(query, []), do: query

  defp filter_tags(query, tags) do
    from e in query, where: fragment("? && ?", e.tags, ^tags)
  end

  defp filter_quest(query, nil), do: query

  defp filter_quest(query, quest_id) do
    from e in query, where: e.thought_id == ^quest_id
  end

  defp apply_sort(query, "importance") do
    from e in query, order_by: [desc_nulls_last: e.importance, desc: e.inserted_at]
  end

  defp apply_sort(query, _newest) do
    from e in query, order_by: [desc: e.inserted_at]
  end
end
