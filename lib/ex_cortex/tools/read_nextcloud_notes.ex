defmodule ExCortex.Tools.ReadNextcloudNotes do
  @moduledoc false

  alias ExCortex.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "read_nextcloud_notes",
      description:
        "List all notes from the Nextcloud Notes app. Returns note ID, title, and category. Example: read_nextcloud_notes() — no parameters needed.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{},
        "required" => []
      },
      callback: &call/1
    )
  end

  def call(_params) do
    case Client.list_notes() do
      {:ok, notes} when is_list(notes) ->
        summary =
          Enum.map_join(notes, "\n", fn n ->
            "- [#{n["id"]}] #{n["title"]} (#{n["category"] || "uncategorized"})"
          end)

        {:ok, if(summary == "", do: "No notes found.", else: summary)}

      {:ok, _} ->
        {:ok, "No notes found."}

      {:error, reason} ->
        {:error, "Failed to list notes: #{inspect(reason)}"}
    end
  end
end
