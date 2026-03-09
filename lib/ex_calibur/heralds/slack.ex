defmodule ExCalibur.Heralds.Slack do
  @moduledoc "Delivers quest output to a Slack channel via Incoming Webhook."

  def deliver(%{config: config}, _quest, body) do
    url = config["webhook_url"] || raise "Slack herald missing webhook_url"
    text = "*#{body.title}*\n\n#{body.body}"

    case Req.post(url, json: %{text: text}) do
      {:ok, %{status: 200}} -> :ok
      {:ok, resp} -> {:error, {:bad_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
