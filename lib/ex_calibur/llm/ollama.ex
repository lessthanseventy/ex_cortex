defmodule ExCalibur.LLM.Ollama do
  @moduledoc "Ollama LLM provider."
  @behaviour ExCalibur.LLM

  alias Excellence.LLM.Ollama

  @impl true
  def complete(model, system_prompt, user_text, opts \\ []) do
    ollama = client(opts)
    chain = Keyword.get(opts, :fallback_chain, Application.get_env(:ex_calibur, :model_fallback_chain, []))
    models = ExCalibur.StepRunner.fallback_models_for(model, chain)

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
    # For now, fall back to plain completion
    complete(model, system_prompt, user_text, opts)
  end

  @impl true
  def configured? do
    url = Application.get_env(:ex_calibur, :ollama_url, "http://127.0.0.1:11434")
    url != nil and url != ""
  end

  defp client(opts) do
    url = Keyword.get(opts, :url, Application.get_env(:ex_calibur, :ollama_url, "http://127.0.0.1:11434"))
    Ollama.new(base_url: url)
  end
end
