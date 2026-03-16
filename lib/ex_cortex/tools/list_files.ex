defmodule ExCortex.Tools.ListFiles do
  @moduledoc "Tool: list files matching a glob pattern."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "list_files",
      description:
        ~s{List files matching a glob pattern. Returns up to 100 file paths. Ignores _build, deps, .git, and node_modules directories. Examples: list_files(pattern: "lib/**/*.ex"), list_files(pattern: "*.md", path: "docs")},
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
  @ignored ~w(_build deps .git .elixir_ls node_modules priv/static/assets)

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
