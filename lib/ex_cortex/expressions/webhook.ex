defmodule ExCortex.Expressions.Webhook do
  @moduledoc "Delivers thought output to any HTTP endpoint via POST."

  def deliver(%{config: config}, thought, body) do
    url = config["url"] || raise "Webhook expression missing url"
    ref = "webhook-#{System.unique_integer([:positive])}"

    payload = %{
      thought_name: thought.name,
      title: body.title,
      body: body.body,
      tags: body.tags,
      importance: body.importance,
      correlation_id: ref
    }

    case Req.post(url, json: payload, headers: Map.to_list(config["headers"] || %{})) do
      {:ok, %{status: s}} when s in 200..299 -> {:ok, ref}
      {:ok, resp} -> {:error, {:bad_status, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
