defmodule ExCalibur.Heralds.Webhook do
  @moduledoc "Delivers quest output to any HTTP endpoint via POST."

  def deliver(%{config: config}, quest, body) do
    url = config["url"] || raise "Webhook herald missing url"
    headers = Map.to_list(config["headers"] || %{})

    payload = %{
      quest_name: quest.name,
      title: body.title,
      body: body.body,
      tags: body.tags,
      importance: body.importance
    }

    case Req.post(url, json: payload, headers: headers) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      {:ok, resp} -> {:error, {:bad_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
