defmodule ExCalibur.Sources.UrlWatcher do
  @moduledoc false
  @behaviour ExCalibur.Sources.Behaviour

  alias ExCalibur.Sources.SourceItem

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

        if hash == state.last_hash do
          {:ok, [], state}
        else
          item = %SourceItem{
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
