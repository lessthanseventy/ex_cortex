defmodule ExCortex.Tools.NextcloudTalk do
  @moduledoc false

  alias ExCortex.Nextcloud.Client

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "nextcloud_talk",
      description:
        "Send a message to a Nextcloud Talk conversation. This is a dangerous tool that sends visible messages.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "token" => %{"type" => "string", "description" => "Talk room token (from room list)"},
          "message" => %{"type" => "string", "description" => "Message to send"}
        },
        "required" => ["token", "message"]
      },
      callback: &call/1
    )
  end

  def call(%{"token" => token, "message" => message}) do
    case Client.talk_send(token, message) do
      {:ok, _} -> {:ok, "Sent message to Talk room #{token}"}
      {:error, reason} -> {:error, "Failed to send Talk message: #{inspect(reason)}"}
    end
  end
end
