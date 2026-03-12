defmodule ExCalibur.Tools.WriteFile do
  @moduledoc "Tool: write content to a file in the working directory."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "write_file",
      description:
        "Write content to a file. Creates parent directories if needed. Path is relative to working directory.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Relative file path to write"},
          "content" => %{"type" => "string", "description" => "File content to write"}
        },
        "required" => ["path", "content"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path, "content" => content} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())
    full_path = Path.join(working_dir, path) |> Path.expand()

    if String.starts_with?(full_path, Path.expand(working_dir)) do
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, content)
      {:ok, "Wrote #{byte_size(content)} bytes to #{path}"}
    else
      {:error, "Path #{path} is outside working directory"}
    end
  end
end
