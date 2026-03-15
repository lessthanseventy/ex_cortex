defmodule ExCortex.Senses.DirectoryWatcher do
  @moduledoc false
  @behaviour ExCortex.Senses.Behaviour

  alias ExCortex.Senses.Item

  @impl true
  def init(config) do
    path = config["path"] || ""

    if path == "" do
      {:error, "path is required"}
    else
      file_mtimes = scan_directory(path, config["patterns"] || ["*"])
      {:ok, %{file_mtimes: file_mtimes}}
    end
  end

  @impl true
  def fetch(state, config) do
    path = config["path"]
    patterns = config["patterns"] || ["*"]
    current_mtimes = scan_directory(path, patterns)

    changed_files =
      Enum.filter(current_mtimes, fn {file_path, mtime} ->
        case Map.get(state.file_mtimes, file_path) do
          nil -> true
          old_mtime -> mtime != old_mtime
        end
      end)

    items =
      Enum.map(changed_files, fn {file_path, _mtime} ->
        content =
          case File.read(file_path) do
            {:ok, data} -> data
            {:error, _} -> ""
          end

        %Item{
          source_id: config["source_id"],
          type: "file",
          content: content,
          metadata: %{
            filename: Path.basename(file_path),
            path: file_path,
            modified_at: File.stat!(file_path).mtime |> NaiveDateTime.from_erl!() |> to_string()
          }
        }
      end)

    {:ok, items, %{state | file_mtimes: current_mtimes}}
  end

  defp scan_directory(path, patterns) do
    patterns
    |> Enum.flat_map(fn pattern ->
      path |> Path.join(pattern) |> Path.wildcard()
    end)
    |> Enum.filter(&File.regular?/1)
    |> Map.new(fn file_path ->
      mtime = File.stat!(file_path).mtime
      {file_path, mtime}
    end)
  end
end
