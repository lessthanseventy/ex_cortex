defmodule ExCortex.Muse do
  @moduledoc """
  Data-grounded single-step LLM queries.

  Wonderings use no context. Musings pull context via RAG over engrams and axioms.
  Both persist the Q&A to the thoughts table.
  """

  alias ExCortex.LLM.Ollama
  alias ExCortex.Memory
  alias ExCortex.Thoughts

  require Logger

  @system_prompt """
  You are a helpful assistant with access to the user's personal knowledge base.
  Answer questions concisely and accurately. If the provided context doesn't help
  answer the question, say so honestly rather than guessing.
  """

  @wonder_system_prompt """
  You are a helpful assistant. Answer questions concisely and accurately.
  """

  @doc """
  Ask a question. Scope determines data grounding:
  - "wonder" — no context, pure LLM
  - "muse" — RAG over engrams and axioms

  Returns `{:ok, %Thought{}}` or `{:error, reason}`.
  """
  def ask(question, opts \\ []) do
    scope = Keyword.get(opts, :scope, "muse")
    source_filters = Keyword.get(opts, :source_filters, [])
    model = Keyword.get(opts, :model, resolve_model())

    {system_prompt, context} =
      case scope do
        "wonder" -> {@wonder_system_prompt, ""}
        _ -> {@system_prompt, gather_context(question, source_filters)}
      end

    user_text = build_user_text(context, question)

    case Ollama.complete(model, system_prompt, user_text) do
      {:ok, answer} ->
        Thoughts.create_thought(%{
          question: question,
          answer: answer,
          scope: scope,
          source_filters: source_filters,
          status: "complete"
        })

      {:error, reason} ->
        Logger.warning("[Muse] LLM call failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Gather RAG context from engrams and axioms."
  def gather_context(question, filters \\ []) do
    engram_context = gather_engram_context(question, filters)
    axiom_context = gather_axiom_context(question)

    [engram_context, axiom_context]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n---\n\n")
  end

  defp gather_engram_context(question, filters) do
    opts = [tier: :L1, limit: 10]

    opts =
      if filters == [] do
        opts
      else
        Keyword.put(opts, :tags, filters)
      end

    engrams = Memory.query(question, opts)

    if engrams == [] do
      ""
    else
      entries =
        Enum.map(engrams, fn e ->
          body = e.recall || e.impression || ""
          "### #{e.title}\n#{body}"
        end)

      "## Relevant Memories\n\n" <> Enum.join(entries, "\n\n")
    end
  end

  defp gather_axiom_context(question) do
    ExCortex.Lexicon.list_axioms()
    |> Enum.map(fn axiom ->
      case ExCortex.Tools.QueryAxiom.call(%{"axiom" => axiom.name, "query" => question}) do
        {:ok, result} ->
          if String.contains?(result, "No matches") do
            nil
          else
            "## #{axiom.name}\n#{result}"
          end

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp build_user_text("", question), do: question

  defp build_user_text(context, question) do
    """
    Use the following context to answer the question. If the context doesn't contain relevant information, say so.

    #{context}

    ---

    Question: #{question}
    """
  end

  defp resolve_model do
    case Application.get_env(:ex_cortex, :model_fallback_chain) do
      [model | _] -> model
      _ -> "devstral-small-2:24b"
    end
  end
end
