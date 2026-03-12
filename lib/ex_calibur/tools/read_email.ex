defmodule ExCalibur.Tools.ReadEmail do
  @moduledoc "Tool: read an email message via notmuch."

  @max_chars 8000

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "read_email",
      description: "Read the full content of an email by its message or thread ID from notmuch search results.",
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
    db_path = ExCalibur.Settings.get(:notmuch_db_path)
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
