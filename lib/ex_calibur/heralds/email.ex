defmodule ExCalibur.Heralds.Email do
  @moduledoc "Sends quest output via email using the Resend API."

  def deliver(%{config: config}, _quest, body) do
    api_key = config["api_key"] || raise "Email herald missing api_key"
    to = config["to"] || raise "Email herald missing to"
    from = config["from"] || raise "Email herald missing from"

    html = "<h2>#{body.title}</h2><pre style=\"white-space:pre-wrap\">#{body.body}</pre>"

    case Req.post("https://api.resend.com/emails",
           json: %{from: from, to: [to], subject: body.title, html: html},
           auth: {:bearer, api_key}
         ) do
      {:ok, %{status: 200}} -> :ok
      {:ok, resp} -> {:error, {:bad_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
