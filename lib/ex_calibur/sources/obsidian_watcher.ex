defmodule ExCalibur.Sources.ObsidianWatcher do
  @moduledoc false
  @behaviour ExCalibur.Sources.Behaviour

  alias ExCalibur.Sources.SourceItem

  require Logger

  @impl true
  def init(config) do
    case list_notes(config) do
      {:ok, notes} ->
        {:ok, %{seen_titles: MapSet.new(notes)}}

      {:error, reason} ->
        Logger.warning("[ObsidianWatcher] init failed: #{inspect(reason)}, starting with empty state")
        {:ok, %{seen_titles: MapSet.new()}}
    end
  end

  @impl true
  def fetch(state, config) do
    case list_notes(config) do
      {:ok, current_notes} ->
        current_set = MapSet.new(current_notes)
        new_titles = current_set |> MapSet.difference(state.seen_titles) |> MapSet.to_list()

        items =
          Enum.flat_map(new_titles, fn title ->
            case fetch_note(title, config) do
              {:ok, content} ->
                [
                  %SourceItem{
                    source_id: config["source_id"],
                    type: "obsidian_note",
                    content: content,
                    metadata: %{title: title}
                  }
                ]

              {:error, reason} ->
                Logger.warning("[ObsidianWatcher] Failed to fetch note '#{title}': #{inspect(reason)}")
                []
            end
          end)

        {:ok, items, %{state | seen_titles: current_set}}

      {:error, reason} ->
        Logger.warning("[ObsidianWatcher] fetch failed: #{inspect(reason)}")
        {:ok, [], state}
    end
  end

  defp list_notes(config) do
    args = build_list_args(config)

    case System.cmd("obsidian-cli", ["list"] ++ args, stderr_to_stdout: true) do
      {output, 0} ->
        notes =
          output
          |> String.split("\n", trim: true)
          |> maybe_filter_folder(config["folder"])

        {:ok, notes}

      {output, code} ->
        {:error, "obsidian-cli exited #{code}: #{output}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp fetch_note(title, config) do
    args = build_vault_args(config)

    case System.cmd("obsidian-cli", ["print", title] ++ args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, "obsidian-cli exited #{code}: #{output}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp build_list_args(config) do
    build_vault_args(config)
  end

  defp build_vault_args(config) do
    case config["vault"] do
      nil -> []
      "" -> []
      vault -> ["--vault", vault]
    end
  end

  defp maybe_filter_folder(notes, nil), do: notes
  defp maybe_filter_folder(notes, ""), do: notes

  defp maybe_filter_folder(notes, folder) do
    prefix = String.trim_trailing(folder, "/") <> "/"
    Enum.filter(notes, &String.starts_with?(&1, prefix))
  end
end
