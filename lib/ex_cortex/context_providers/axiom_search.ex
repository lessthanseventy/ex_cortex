defmodule ExCortex.ContextProviders.AxiomSearch do
  @moduledoc """
  Searches all axioms for matches against the input question.

  Unlike the Axiom provider (which loads a specific axiom by ID),
  this searches across all axioms for relevant content.

  No config options needed.
  """

  @behaviour ExCortex.ContextProviders.ContextProvider

  @impl true
  def build(_config, _thought, input) do
    ExCortex.Lexicon.list_axioms()
    |> Enum.map(fn axiom ->
      case ExCortex.Tools.QueryAxiom.call(%{"axiom" => axiom.name, "query" => input}) do
        {:ok, result} ->
          if String.contains?(result, "No matches"), do: nil, else: "## #{axiom.name}\n#{result}"

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end
end
