defmodule ExCalibur.Tools.SearchNextcloud do
  @moduledoc false

  alias ExCalibur.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "search_nextcloud",
      description: "Search for files in Nextcloud by listing a directory path via WebDAV.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Directory path to search, e.g. '/Documents' or '/'"}
        },
        "required" => ["path"]
      },
      callback: &call/1
    )
  end

  def call(%{"path" => path}) do
    case Client.propfind(path) do
      {:ok, entries} -> {:ok, Enum.join(entries, "\n")}
      {:error, reason} -> {:error, "Search failed: #{inspect(reason)}"}
    end
  end
end
