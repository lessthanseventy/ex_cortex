defmodule ExCortex.Tools.CreateNextcloudNote do
  @moduledoc false

  alias ExCortex.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "create_nextcloud_note",
      description: "Create a new note in Nextcloud Notes app.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "title" => %{"type" => "string", "description" => "Note title"},
          "content" => %{"type" => "string", "description" => "Note content (markdown supported)"},
          "category" => %{"type" => "string", "description" => "Optional category/folder for the note"}
        },
        "required" => ["title", "content"]
      },
      callback: &call/1
    )
  end

  def call(%{"title" => title, "content" => content} = params) do
    category = params["category"] || ""

    case Client.create_note(title, content, category) do
      {:ok, note} -> {:ok, "Created note '#{title}' (id: #{note["id"]})"}
      {:error, reason} -> {:error, "Failed to create note: #{inspect(reason)}"}
    end
  end
end
