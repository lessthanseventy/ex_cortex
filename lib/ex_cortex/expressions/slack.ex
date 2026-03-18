defmodule ExCortex.Expressions.Slack do
  @moduledoc "Delivers thought output to a Slack channel via Incoming Webhook."

  def deliver(%{config: config}, _thought, body) do
    url = config["webhook_url"] || raise "Slack expression missing webhook_url"
    text = "*#{body.title}*\n\n#{body.body}"
    ref = "slack-#{System.unique_integer([:positive])}"

    case Req.post(url, json: %{text: text}) do
      {:ok, %{status: 200}} -> {:ok, ref}
      {:ok, resp} -> {:error, {:bad_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
