defmodule ExCortex.Tools.EmailTag do
  @moduledoc "Tool: add or remove tags on email threads via notmuch."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "email_tag",
      description:
        "Add or remove tags on an email thread. Use +tag to add, -tag to remove. " <>
          "Example: thread_id='0000000000000042', tags='+archived -inbox' to archive a thread.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "thread_id" => %{"type" => "string", "description" => "The notmuch thread ID"},
          "tags" => %{
            "type" => "string",
            "description" => "Tags to add/remove, e.g. '+archived -inbox -unread'"
          }
        },
        "required" => ["thread_id", "tags"]
      },
      callback: &call/1
    )
  end

  def call(%{"thread_id" => thread_id, "tags" => tags}) do
    tag_args = String.split(tags)
    args = ["tag"] ++ tag_args ++ ["--", "thread:#{thread_id}"]

    case System.cmd("notmuch", args, stderr_to_stdout: true) do
      {_output, 0} -> {:ok, "Tagged thread #{thread_id}: #{tags}"}
      {output, code} -> {:error, "notmuch tag failed (exit #{code}): #{String.trim(output)}"}
    end
  rescue
    e -> {:error, "notmuch not available: #{Exception.message(e)}"}
  end
end
