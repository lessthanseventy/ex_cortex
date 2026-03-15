defmodule ExCortex.ContextProviders.Axiom do
  @moduledoc """
  Injects an axiom's content as prompt context.

  Config options:
    "axiom_id" - the integer ID of the axiom to load (required)
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  alias ExCortex.Lexicon

  @impl true
  def build(%{"axiom_id" => axiom_id}, _thought, _input) do
    case Lexicon.get_axiom(axiom_id) do
      nil ->
        ""

      axiom ->
        String.trim("""
        ## Reference: #{axiom.name}
        #{axiom.content}
        """)
    end
  end

  # Support old config key
  def build(%{"dictionary_id" => id}, thought, input), do: build(%{"axiom_id" => id}, thought, input)

  def build(_config, _thought, _input), do: ""
end
