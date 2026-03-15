defmodule ExCortex.Core.LLM do
  @moduledoc "LLM provider abstraction for the agent evaluation pipeline."

  @type message :: %{role: String.t(), content: String.t()}

  @callback chat(provider :: struct(), model :: String.t(), messages :: [message()], opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  def chat(%module{} = provider, model, messages, opts \\ []) do
    module.chat(provider, model, messages, opts)
  end
end
