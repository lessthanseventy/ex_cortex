defmodule ExCalibur.Tools.ListFiles do
  @moduledoc "Tool: list files matching a glob pattern."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "list_files",
      description: "List files matching a glob pattern. Only searches app source directories (lib/, test/, config/, priv/repo/, docs/) — not deps or path dependencies.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{
            "type" => "string",
            "description" => "Glob pattern (e.g. '**/*.ex', 'lib/**/*.ex')"
          },
          "path" => %{
            "type" => "string",
            "description" => "Subdirectory to search in (optional)"
          }
        },
        "required" => ["pattern"]
      },
      callback: &call/1
    )
  end

  # Directories that are never relevant to the app's own source code
  @ignored ~w(_build deps .git .elixir_ls node_modules priv/static/assets
              ex_cellence ex_cellence_dashboard ex_cellence_ui)

  def call(%{"pattern" => pattern} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())
    subdir = Map.get(params, "path", "")
    search_dir = if subdir == "", do: working_dir, else: Path.join(working_dir, subdir)

    files =
      search_dir
      |> Path.join(pattern)
      |> Path.wildcard()
      |> Enum.map(&Path.relative_to(&1, working_dir))
      |> Enum.reject(fn path ->
        Enum.any?(@ignored, &String.starts_with?(path, &1))
      end)
      |> Enum.sort()
      |> Enum.take(100)

    {:ok, Enum.join(files, "\n")}
  end
end
