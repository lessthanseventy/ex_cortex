defmodule ExCortex.Obsidian.Sync do
  @moduledoc """
  Syncs engrams and signal cards to the Obsidian vault as markdown files.
  Called as a fire-and-forget side effect after DB writes.
  """

  alias ExCortex.Settings

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
  def sync_engram(entry) do
    with true <- sync_enabled?(),
         path when not is_nil(path) <- vault_path() do
      Task.Supervisor.start_child(ExCortex.AsyncTaskSupervisor, fn ->
        do_sync_engram(entry, path)
      end)
    else
      _ -> :skipped
    end
  end

  @doc """
  Called synchronously from the creating process (which has DB access).
  Spawns a background task only if sync is enabled; the task does no DB queries.
  """
  def sync_signal(card) do
    with true <- sync_enabled?(),
         path when not is_nil(path) <- vault_path() do
      Task.Supervisor.start_child(ExCortex.AsyncTaskSupervisor, fn ->
        do_sync_signal(card, path)
      end)
    else
      _ -> :skipped
    end
  end

  defp do_sync_engram(entry, vault_path) do
    dir = Path.join([vault_path, "ExCortex", "Memory"])
    File.mkdir_p!(dir)
    slug = slugify(entry.title || "entry", entry.inserted_at)
    file_path = Path.join(dir, "#{slug}.md")

    tags = Enum.join(entry.tags || [], ", ")

    content = """
    ---
    type: engram
    thought_id: #{entry.thought_id}
    tags: [#{tags}]
    importance: #{entry.importance || 0}
    created: #{to_iso8601(entry.inserted_at)}
    ---

    # #{entry.title || "engram"}

    #{entry.body || ""}
    """

    File.write(file_path, content)
    Logger.debug("[Obsidian.Sync] Synced engram to #{file_path}")
    {:ok, file_path}
  rescue
    e -> Logger.warning("[Obsidian.Sync] Failed to sync engram: #{Exception.message(e)}")
  end

  defp do_sync_signal(card, vault_path) do
    dir = Path.join([vault_path, "ExCortex", "Cortex"])
    File.mkdir_p!(dir)
    slug = slugify(card.title || "card", card.inserted_at)
    file_path = Path.join(dir, "#{slug}.md")

    content = """
    ---
    type: signal
    card_type: #{card.type || "note"}
    created: #{to_iso8601(card.inserted_at)}
    ---

    # #{card.title || "signal card"}

    #{card.body || ""}
    """

    File.write(file_path, content)
    Logger.debug("[Obsidian.Sync] Synced signal card to #{file_path}")
    {:ok, file_path}
  rescue
    e -> Logger.warning("[Obsidian.Sync] Failed to sync signal card: #{Exception.message(e)}")
  end

  defp slugify(title, %DateTime{} = datetime) do
    date = datetime |> DateTime.to_date() |> Date.to_iso8601()

    slug =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 50)

    "#{date}-#{slug}"
  end

  defp slugify(title, %NaiveDateTime{} = datetime) do
    date = datetime |> NaiveDateTime.to_date() |> Date.to_iso8601()

    slug =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 50)

    "#{date}-#{slug}"
  end

  defp slugify(title, nil) do
    date = Date.to_iso8601(Date.utc_today())

    slug =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 50)

    "#{date}-#{slug}"
  end

  defp to_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp to_iso8601(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp to_iso8601(nil), do: ""
end
