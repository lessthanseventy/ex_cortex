defmodule ExCortex.Tools.ReadFile do
  @moduledoc "Tool: read a file from the working directory."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "read_file",
      description:
        "Read a file from the local project filesystem (relative paths only). Use list_files to discover available files. Returns full file content. Example: read_file(path: \"lib/ex_cortex/muse.ex\")",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Relative file path to read"}
        },
        "required" => ["path"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())
    full_path = working_dir |> Path.join(path) |> Path.expand()

    if String.starts_with?(full_path, Path.expand(working_dir)) do
      case File.read(full_path) do
        {:ok, content} -> {:ok, content}
        {:error, reason} -> {:error, "Cannot read #{path}: #{reason}"}
      end
    else
      {:error, "Path #{path} is outside working directory"}
    end
  end
end
