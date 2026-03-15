defmodule ExCortex.Senses.UrlWatcher do
  @moduledoc false
  @behaviour ExCortex.Senses.Behaviour

  alias ExCortex.Senses.Item

  @impl true
  def init(_config) do
    {:ok, %{last_hash: nil, last_content: nil}}
  end

  @impl true
  def fetch(state, config) do
    url = config["url"]

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        body_str = if is_binary(body), do: body, else: Jason.encode!(body)
        hash = :sha256 |> :crypto.hash(body_str) |> Base.encode16()

        always_fire = Map.get(config, "always_fire", false)

        if hash == state.last_hash and not always_fire do
          {:ok, [], state}
        else
          item = %Item{
            source_id: config["source_id"],
            type: "url_diff",
            content: body_str,
            metadata: %{url: url, previous_hash: state.last_hash, new_hash: hash}
          }

          {:ok, [item], %{state | last_hash: hash, last_content: body_str}}
        end

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
