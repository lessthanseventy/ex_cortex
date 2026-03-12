defmodule ExCalibur.LLM.Ollama do
  @moduledoc "Ollama LLM provider."
  @behaviour ExCalibur.LLM

  alias Excellence.LLM.Ollama

  @impl true
  def complete(model, system_prompt, user_text, opts \\ []) do
    ollama = client(opts)
    chain = Keyword.get(opts, :fallback_chain, Application.get_env(:ex_calibur, :model_fallback_chain, []))
    models = fallback_models_for(model, chain)

    messages = [
      %{role: :system, content: system_prompt},
      %{role: :user, content: user_text}
    ]

    Enum.reduce_while(models, {:error, :all_models_failed}, fn m, acc ->
      case Ollama.chat(ollama, m, messages) do
        {:ok, text} when is_binary(text) -> {:halt, {:ok, text}}
        _ -> {:cont, acc}
      end
    end)
  end

  @impl true
  def complete_with_tools(model, system_prompt, user_text, _tools, opts \\ []) do
    # TODO: Wire Ollama native tool calling when available
    # For now, fall back to plain completion (no tool log)
    case complete(model, system_prompt, user_text, opts) do
      {:ok, text} -> {:ok, text, []}
      error -> error
    end
  end

  @impl true
  def configured? do
    url = Application.get_env(:ex_calibur, :ollama_url, "http://127.0.0.1:11434")
    url != nil and url != ""
  end

  @doc "Build ordered list of models to try: assigned model first, then fallback chain (deduped)."
  def fallback_models_for(model, chain) do
    [model | Enum.reject(chain, &(&1 == model))]
  end

  defp client(opts) do
    url = Keyword.get(opts, :url, Application.get_env(:ex_calibur, :ollama_url, "http://127.0.0.1:11434"))
    api_key = Keyword.get(opts, :api_key, Application.get_env(:ex_calibur, :ollama_api_key))
    Ollama.new(base_url: url, api_key: api_key)
  end
end
