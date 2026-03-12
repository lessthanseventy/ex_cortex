defmodule ExCalibur.LLM do
  @moduledoc """
  Unified LLM provider abstraction.

  Dispatches to provider-specific modules based on the provider string
  stored in member config. Supports Ollama, Claude, and is extensible
  for future providers (OpenAI, Groq, etc.).

  ## Usage

      ExCalibur.LLM.complete("ollama", "llama3:8b", system_prompt, user_text)
      ExCalibur.LLM.complete("claude", "claude-sonnet-4-6", system_prompt, user_text)
  """

  alias ExCalibur.LLM.Ollama

  @callback complete(model :: String.t(), system_prompt :: String.t(), user_text :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @callback complete_with_tools(
              model :: String.t(),
              system_prompt :: String.t(),
              user_text :: String.t(),
              tools :: [map()],
              opts :: keyword()
            ) :: {:ok, String.t(), [map()]} | {:error, term()}

  @callback configured?() :: boolean()

  @providers %{
    "ollama" => Ollama,
    "claude" => ExCalibur.LLM.Claude
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

  def configured?(provider) do
    provider_for(provider).configured?()
  end
end
