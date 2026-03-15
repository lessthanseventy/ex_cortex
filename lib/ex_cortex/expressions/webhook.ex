defmodule ExCortex.Expressions.Webhook do
  @moduledoc "Delivers thought output to any HTTP endpoint via POST."

  def deliver(%{config: config}, thought, body) do
    url = config["url"] || raise "Webhook expression missing url"
    headers = Map.to_list(config["headers"] || %{})

    payload = %{
      thought_name: thought.name,
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
