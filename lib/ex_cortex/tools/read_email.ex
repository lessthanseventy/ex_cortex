defmodule ExCortex.Tools.ReadEmail do
  @moduledoc "Tool: read an email message via notmuch."

  @max_chars 8000

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "read_email",
      description:
        "Read the full content of an email thread or message by ID (from search_email results). Output capped at 8000 characters. Use search_email first to find thread/message IDs. Example: read_email(id: \"thread:00000000000001a3\")",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "string", "description" => "Message ID or thread ID from notmuch search results"}
        },
        "required" => ["id"]
      },
      callback: &call/1
    )
  end

  def call(%{"id" => id}) do
    db_path = ExCortex.Settings.get(:notmuch_db_path)
    args = build_args(db_path, id)

    case System.cmd("notmuch", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, String.slice(output, 0, @max_chars)}

      {error, _} ->
        {:error, error}
    end
  end

  defp build_args(nil, id) do
    ["show", "--format=text", "--body=true", id]
  end

  defp build_args(db_path, id) do
    ["--config=#{db_path}", "show", "--format=text", "--body=true", id]
  end
end
