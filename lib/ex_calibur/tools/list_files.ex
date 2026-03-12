defmodule ExCalibur.Tools.ListFiles do
  @moduledoc "Tool: list files matching a glob pattern."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "list_files",
      description: "List files matching a glob pattern in the working directory.",
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

  def call(%{"pattern" => pattern} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())
    subdir = Map.get(params, "path", "")
    search_dir = if subdir == "", do: working_dir, else: Path.join(working_dir, subdir)

    files =
      Path.join(search_dir, pattern)
      |> Path.wildcard()
      |> Enum.map(&Path.relative_to(&1, working_dir))
      |> Enum.sort()
      |> Enum.take(100)

    {:ok, Enum.join(files, "\n")}
  end
end
