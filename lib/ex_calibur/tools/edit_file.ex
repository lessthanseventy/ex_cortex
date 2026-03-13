defmodule ExCalibur.Tools.EditFile do
  @moduledoc "Tool: find-and-replace text in a file."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "edit_file",
      description: "Replace a specific string in a file. The old string must appear exactly once.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Relative file path"},
          "old" => %{"type" => "string", "description" => "Exact text to find"},
          "new" => %{"type" => "string", "description" => "Replacement text"}
        },
        "required" => ["path", "old", "new"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path, "old" => old, "new" => new} = params) do
    working_dir = Map.get(params, "working_dir", File.cwd!())
    full_path = working_dir |> Path.join(path) |> Path.expand()

    if String.starts_with?(full_path, Path.expand(working_dir)) do
      do_replace(full_path, path, old, new)
    else
      {:error, "Path #{path} is outside working directory"}
    end
  end

  defp do_replace(full_path, path, old, new) do
    case File.read(full_path) do
      {:ok, content} ->
        count = length(String.split(content, old)) - 1

        cond do
          count == 0 ->
            {:error, "Text not found in #{path}"}

          count > 1 ->
            {:error, "Text appears #{count} times in #{path} — must be unique"}

          true ->
            File.write!(full_path, String.replace(content, old, new, global: false))
            {:ok, "Replaced text in #{path}"}
        end

      {:error, reason} ->
        {:error, "Cannot read #{path}: #{reason}"}
    end
  end
end
