defmodule ExCalibur.LLM.Ollama do
  @moduledoc "Ollama LLM provider."
  @behaviour ExCalibur.LLM

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

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

    Tracer.with_span "llm.complete", %{
      attributes: %{
        "llm.provider" => "ollama",
        "llm.model" => model,
        "llm.input_bytes" => byte_size(user_text)
      }
    } do
      result =
        Enum.reduce_while(models, {:error, :all_models_failed}, fn m, acc ->
          t0 = System.monotonic_time(:millisecond)
          Logger.debug("[Ollama] → #{m} (#{byte_size(user_text)}B input)")

          case Ollama.chat(ollama, m, messages) do
            {:ok, text} when is_binary(text) ->
              ms = System.monotonic_time(:millisecond) - t0
              Logger.info("[Ollama] ✓ #{m} #{ms}ms (#{byte_size(text)}B output)")
              {:halt, {:ok, text}}

            {:error, reason} ->
              ms = System.monotonic_time(:millisecond) - t0
              Logger.warning("[Ollama] ✗ #{m} failed after #{ms}ms: #{inspect(reason)}")
              {:cont, acc}

            other ->
              Logger.warning("[Ollama] ✗ #{m} unexpected response: #{inspect(other)}")
              {:cont, acc}
          end
        end)

      case result do
        {:ok, text} ->
          Tracer.set_attributes(%{"llm.output_bytes" => byte_size(text), "llm.status" => "ok"})

        _ ->
          Tracer.set_attributes(%{"llm.status" => "error"})
      end

      result
    end
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
