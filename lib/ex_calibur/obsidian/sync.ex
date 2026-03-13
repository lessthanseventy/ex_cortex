defmodule ExCalibur.Obsidian.Sync do
  @moduledoc """
  Syncs lore entries and lodge cards to the Obsidian vault as markdown files.
  Called as a fire-and-forget side effect after DB writes.
  """

  alias ExCalibur.Settings

  require Logger

  def sync_enabled? do
    Settings.get(:obsidian_sync_enabled) == true
  rescue
    _ -> false
  end

  def vault_path do
    Settings.get(:obsidian_vault_path)
  rescue
    _ -> nil
  end

  @doc """
  Called synchronously from the creating process (which has DB access).
  Spawns a background task only if sync is enabled; the task does no DB queries.
  """
  def sync_lore_entry(entry) do
    with true <- sync_enabled?(),
         path when not is_nil(path) <- vault_path() do
      Task.Supervisor.start_child(ExCalibur.AsyncTaskSupervisor, fn ->
        do_sync_lore(entry, path)
      end)
    else
      _ -> :skipped
    end
  end

  @doc """
  Called synchronously from the creating process (which has DB access).
  Spawns a background task only if sync is enabled; the task does no DB queries.
  """
  def sync_lodge_card(card) do
    with true <- sync_enabled?(),
         path when not is_nil(path) <- vault_path() do
      Task.Supervisor.start_child(ExCalibur.AsyncTaskSupervisor, fn ->
        do_sync_lodge(card, path)
      end)
    else
      _ -> :skipped
    end
  end

  defp do_sync_lore(entry, vault_path) do
    dir = Path.join([vault_path, "ExCalibur", "Lore"])
    File.mkdir_p!(dir)
    slug = slugify(entry.title || "entry", entry.inserted_at)
    file_path = Path.join(dir, "#{slug}.md")

    tags = Enum.join(entry.tags || [], ", ")

    content = """
    ---
    type: lore_entry
    quest_id: #{entry.quest_id}
    tags: [#{tags}]
    importance: #{entry.importance || 0}
    created: #{DateTime.to_iso8601(entry.inserted_at)}
    ---

    # #{entry.title || "Lore Entry"}

    #{entry.body || ""}
    """

    File.write(file_path, content)
    Logger.debug("[Obsidian.Sync] Synced lore entry to #{file_path}")
    {:ok, file_path}
  rescue
    e -> Logger.warning("[Obsidian.Sync] Failed to sync lore entry: #{Exception.message(e)}")
  end

  defp do_sync_lodge(card, vault_path) do
    dir = Path.join([vault_path, "ExCalibur", "Lodge"])
    File.mkdir_p!(dir)
    slug = slugify(card.title || "card", card.inserted_at)
    file_path = Path.join(dir, "#{slug}.md")

    content = """
    ---
    type: lodge_card
    card_type: #{card.type || "note"}
    created: #{DateTime.to_iso8601(card.inserted_at)}
    ---

    # #{card.title || "Lodge Card"}

    #{card.body || ""}
    """

    File.write(file_path, content)
    Logger.debug("[Obsidian.Sync] Synced lodge card to #{file_path}")
    {:ok, file_path}
  rescue
    e -> Logger.warning("[Obsidian.Sync] Failed to sync lodge card: #{Exception.message(e)}")
  end

  defp slugify(title, datetime) do
    date = datetime |> DateTime.to_date() |> Date.to_iso8601()

    slug =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 50)

    "#{date}-#{slug}"
  end
end
