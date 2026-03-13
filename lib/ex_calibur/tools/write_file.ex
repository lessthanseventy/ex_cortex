defmodule ExCalibur.Tools.WriteFile do
  @moduledoc "Tool: write content to a file in the working directory."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "write_file",
      description:
        "Write content to a file. Creates parent directories if needed. Path is relative to working_dir. REQUIRED: always pass working_dir as the worktree path returned by setup_worktree.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Relative file path to write"},
          "content" => %{"type" => "string", "description" => "File content to write"},
          "working_dir" => %{
            "type" => "string",
            "description" => "Absolute path to the worktree directory (from setup_worktree)"
          }
        },
        "required" => ["path", "content", "working_dir"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path, "content" => content} = params) do
    working_dir = Map.get(params, "working_dir") || File.cwd!()
    full_path = working_dir |> Path.join(path) |> Path.expand()

    if String.starts_with?(full_path, Path.expand(working_dir)) do
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, content)
      {:ok, "Wrote #{byte_size(content)} bytes to #{path}"}
    else
      {:error, "Path #{path} is outside working directory"}
    end
  end
end
