defmodule ExCortex.LLM do
  @moduledoc """
  Unified LLM provider abstraction.

  Dispatches to provider-specific modules based on the provider string
  stored in neuron config. Supports Ollama, Claude, and is extensible
  for future providers (OpenAI, Groq, etc.).

  ## Usage

      ExCortex.LLM.complete("ollama", "llama3:8b", system_prompt, user_text)
      ExCortex.LLM.complete("claude", "claude-sonnet-4-6", system_prompt, user_text)
  """

  alias ExCortex.LLM.Ollama

  @callback complete(model :: String.t(), system_prompt :: String.t(), user_text :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @callback complete_with_tools(
              model :: String.t(),
              system_prompt :: String.t(),
              user_text :: String.t(),
              tools :: [map()],
              opts :: keyword()
            ) :: {:ok, String.t(), [map()]} | {:error, term()}

  @callback stream_complete(
              model :: String.t(),
              system_prompt :: String.t(),
              user_text :: String.t(),
              opts :: keyword()
            ) :: {:ok, Enumerable.t()} | {:error, term()}

  @callback configured?() :: boolean()

  @optional_callbacks [stream_complete: 4]

  @providers %{
    "ollama" => Ollama,
    "claude" => ExCortex.LLM.Claude
  }

  def provider_for(nil), do: Ollama
  def provider_for(""), do: Ollama
  def provider_for(name), do: Map.get(@providers, name, Ollama)

  def providers, do: @providers

  def complete(provider, model, system_prompt, user_text, opts \\ []) do
    provider_for(provider).complete(model, system_prompt, user_text, opts)
  end

  def complete_with_tools(provider, model, system_prompt, user_text, tools, opts \\ []) do
    provider_for(provider).complete_with_tools(model, system_prompt, user_text, tools, opts)
  end

  def stream_complete(provider, model, system_prompt, user_text, opts \\ []) do
    mod = provider_for(provider)

    if function_exported?(mod, :stream_complete, 4) do
      mod.stream_complete(model, system_prompt, user_text, opts)
    else
      # Fallback: blocking call emitted as a single token
      case mod.complete(model, system_prompt, user_text, opts) do
        {:ok, text} -> {:ok, [{:token, text}, {:done, text}]}
        error -> error
      end
    end
  end

  def configured?(provider) do
    provider_for(provider).configured?()
  end
end
