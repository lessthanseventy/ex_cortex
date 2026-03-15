defmodule ExCortex.ContextProviders.Static do
  @moduledoc """
  Injects a fixed string into the prompt preamble.
  Config: %{"type" => "static", "content" => "Always consider X when reviewing."}
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  @impl true
  def build(%{"content" => content}, _quest, _input) when is_binary(content) do
    String.trim(content)
  end

  def build(_config, _quest, _input), do: ""
end
