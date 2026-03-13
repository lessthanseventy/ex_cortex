defmodule ExCalibur.ContextProviders.FileReader do
  @moduledoc """
  Injects the contents of specific files as prompt context.

  The model receives file contents directly — no read_file tool call needed.

  Config:
    "files"  - list of relative file paths to read (from project root)
    "label"  - optional section header (default: "## Codebase Files")
    "max_bytes_per_file" - optional per-file truncation limit (default: 4000)

  Example:
    %{
      "type" => "file_reader",
      "files" => ["lib/ex_calibur/quest_runner.ex", "lib/ex_calibur/step_runner.ex"]
    }
  """

  @behaviour ExCalibur.ContextProviders.ContextProvider

  require Logger

  @default_max_bytes 4_000

  @impl true
  def build(config, _quest, _input) do
    files = Map.get(config, "files", [])
    label = Map.get(config, "label", "## Codebase Files")
    max_bytes = Map.get(config, "max_bytes_per_file", @default_max_bytes)
    root = File.cwd!()

    sections =
      Enum.map(files, fn path ->
        full_path = Path.join(root, path)

        case File.read(full_path) do
          {:ok, content} ->
            truncated = String.slice(content, 0, max_bytes)
            suffix = if byte_size(content) > max_bytes, do: "\n... (truncated)", else: ""
            "### #{path}\n```elixir\n#{truncated}#{suffix}\n```"

          {:error, reason} ->
            Logger.debug("[FileReaderCtx] Could not read #{path}: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if sections == [] do
      ""
    else
      """
      #{label}

      #{Enum.join(sections, "\n\n")}
      """
      |> String.trim()
    end
  end
end
