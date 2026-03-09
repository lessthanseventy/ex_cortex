defmodule ExCalibur.Heralds.PagerDuty do
  @moduledoc "Triggers a PagerDuty incident with quest output as the summary."

  def deliver(%{config: config}, quest, body) do
    routing_key = config["routing_key"] || raise "PagerDuty herald missing routing_key"

    payload = %{
      routing_key: routing_key,
      event_action: "trigger",
      payload: %{
        summary: body.title,
        severity: config["severity"] || "error",
        source: quest.name,
        custom_details: %{body: body.body, tags: body.tags}
      }
    }

    case Req.post("https://events.pagerduty.com/v2/enqueue", json: payload) do
      {:ok, %{status: 202}} -> :ok
      {:ok, resp} -> {:error, {:bad_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
