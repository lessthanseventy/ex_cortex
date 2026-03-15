defmodule ExCortex.OllamaCache do
  @moduledoc false
  @ttl_ms 30_000
  @key :ollama_status_cache

  def get_status do
    case :persistent_term.get(@key, nil) do
      {result, cached_at} ->
        if System.monotonic_time(:millisecond) - cached_at < @ttl_ms do
          result
        else
          fetch_and_cache()
        end

      nil ->
        fetch_and_cache()
    end
  end

  def get_models do
    %{models: models} = get_status()
    models
  end

  defp fetch_and_cache do
    url = Application.get_env(:ex_cortex, :ollama_url, "http://127.0.0.1:11434")
    api_key = Application.get_env(:ex_cortex, :ollama_api_key)
    headers = if api_key, do: [{"authorization", "Bearer #{api_key}"}], else: []

    result =
      case Req.get("#{url}/api/tags",
             headers: headers,
             receive_timeout: 2_000,
             connect_options: [timeout: 2_000]
           ) do
        {:ok, %{status: 200, body: %{"models" => models}}} ->
          %{reachable: true, url: url, models: Enum.map(models, & &1["name"])}

        _ ->
          %{reachable: false, url: url, models: []}
      end

    :persistent_term.put(@key, {result, System.monotonic_time(:millisecond)})
    result
  rescue
    _ ->
      url = Application.get_env(:ex_cortex, :ollama_url, "http://127.0.0.1:11434")
      %{reachable: false, url: url, models: []}
  end
end
