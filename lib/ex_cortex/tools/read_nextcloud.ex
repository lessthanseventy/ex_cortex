defmodule ExCortex.Tools.ReadNextcloud do
  @moduledoc false

  alias ExCortex.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "read_nextcloud",
      description: "Read a file from Nextcloud by its path.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "File path in Nextcloud, e.g. '/Documents/notes.md'"}
        },
        "required" => ["path"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path}) do
    case Client.get_file(path) do
      {:ok, content} -> {:ok, content}
      {:error, :not_found} -> {:error, "File not found: #{path}"}
      {:error, reason} -> {:error, "Read failed: #{inspect(reason)}"}
    end
  end
end
