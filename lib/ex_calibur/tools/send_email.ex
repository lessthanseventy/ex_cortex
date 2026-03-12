defmodule ExCalibur.Tools.SendEmail do
  @moduledoc "Tool: send an email via msmtp."

  def req_llm_tool do
    ReqLLM.Tool.new!(
      name: "send_email",
      description: "Send an email via msmtp. Builds an RFC822 message and pipes it to msmtp.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "to" => %{"type" => "string", "description" => "Recipient email address"},
          "subject" => %{"type" => "string", "description" => "Email subject line"},
          "body" => %{"type" => "string", "description" => "Plain-text email body"},
          "from" => %{
            "type" => "string",
            "description" => "Sender email address (optional, uses msmtp account default if omitted)"
          }
        },
        "required" => ["to", "subject", "body"]
      },
      callback: &call/1
    )
  end

  def call(%{"to" => to, "subject" => subject, "body" => body} = params) do
    from = Map.get(params, "from", "")
    account = ExCalibur.Settings.get(:msmtp_account)
    message = build_message(from, to, subject, body)
    args = build_args(account, to)

    case System.cmd("msmtp", args, input: message, stderr_to_stdout: true) do
      {_output, 0} -> {:ok, "Email sent to #{to}"}
      {error, _} -> {:error, error}
    end
  end

  defp build_message("", to, subject, body) do
    "To: #{to}\nSubject: #{subject}\n\n#{body}\n"
  end

  defp build_message(from, to, subject, body) do
    "From: #{from}\nTo: #{to}\nSubject: #{subject}\n\n#{body}\n"
  end

  defp build_args(nil, to), do: [to]
  defp build_args(account, to), do: ["-a", account, to]
end
