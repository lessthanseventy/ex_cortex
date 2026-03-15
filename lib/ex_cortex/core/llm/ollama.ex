defmodule ExCortex.Core.LLM.Ollama do
  @moduledoc "Ollama provider for the agent evaluation pipeline (simple chat, no tool calling)."
  @behaviour ExCortex.Core.LLM

  defstruct [:base_url, :timeout, :api_key]

  def new(opts \\ []) do
    %__MODULE__{
      base_url: Keyword.get(opts, :base_url, "http://127.0.0.1:11434"),
      timeout: Keyword.get(opts, :timeout, 120_000),
      api_key: Keyword.get(opts, :api_key)
    }
  end

  @impl true
  def chat(%__MODULE__{} = provider, model, messages, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, provider.timeout)
    url = provider.base_url <> "/api/chat"
    body = %{model: model, messages: messages, stream: false}

    headers =
      if provider.api_key,
        do: [{"authorization", "Bearer #{provider.api_key}"}],
        else: []

    case Req.post(url,
           json: body,
           headers: headers,
           connect_options: [timeout: 10_000],
           receive_timeout: timeout
         ) do
      {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
        {:ok, content}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ollama_error, status, body}}

      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  end
end
