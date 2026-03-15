defmodule ExCortex.ContextProviders.Dictionary do
  @moduledoc """
  Injects a dictionary's content as prompt context.

  Config options:
    "dictionary_id" - the integer ID of the dictionary to load (required)
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  alias ExCortex.Library

  @impl true
  def build(%{"dictionary_id" => dict_id}, _quest, _input) do
    case Library.get_dictionary(dict_id) do
      nil ->
        ""

      dict ->
        String.trim("""
        ## Reference: #{dict.name}
        #{dict.content}
        """)
    end
  end

  def build(_config, _quest, _input), do: ""
end
