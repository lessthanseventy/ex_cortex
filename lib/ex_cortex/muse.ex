defmodule ExCortex.Muse do
  @moduledoc """
  Data-grounded single-step LLM queries.

  Wonderings use no context. Musings pull context via RAG over engrams and axioms.
  Both persist the Q&A to the thoughts table.
  """

  alias ExCortex.LLM
  alias ExCortex.Memory
  alias ExCortex.Signals.Signal
  alias ExCortex.Thoughts
  alias ExCortex.Tools.Registry

  require Logger

  @system_prompt """
  You are a helpful assistant with access to the user's personal knowledge base, dashboard signals, and a set of tools.
  Answer questions concisely and accurately. When the user asks about recent news, digests, or summaries,
  check the Dashboard Signals section first — these contain recent digest outputs with links.
  Use your tools to look up information the user asks about — search email, query memory, fetch URLs, read files, etc.
  If neither the provided context nor your tools can answer the question, say so honestly rather than guessing.
  When your context includes links, include them in your answer.
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
    history = Keyword.get(opts, :history, [])

    {system_prompt, context} =
      case scope do
        "wonder" -> {@wonder_system_prompt, ""}
        _ -> {@system_prompt, gather_context(question, source_filters)}
      end

    user_text = build_user_text(context, question)

    provider = provider_for(model)

    result =
      case scope do
        "wonder" ->
          LLM.complete(provider, model, system_prompt, user_text, history: history)

        _ ->
          tools = Registry.list_safe()

          case LLM.complete_with_tools(provider, model, system_prompt, user_text, tools, history: history) do
            {:ok, answer, _tool_log} -> {:ok, answer}
            {:error, reason, _tool_log} -> {:error, reason}
            {:error, reason} -> {:error, reason}
          end
      end

    case result do
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

  @doc "Gather RAG context from signals, engrams, and axioms."
  def gather_context(question, filters \\ []) do
    source_context = gather_source_context()
    signal_context = gather_signal_context(question)
    engram_context = gather_engram_context(question, filters)
    axiom_context = gather_axiom_context(question)

    [source_context, signal_context, engram_context, axiom_context]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n---\n\n")
  end

  defp gather_source_context do
    import Ecto.Query

    senses =
      from(s in ExCortex.Senses.Sense, where: s.status != "error", order_by: s.name)
      |> ExCortex.Repo.all()
      |> Enum.map(fn s ->
        status = if s.status == "paused", do: " [paused]", else: ""

        last =
          if s.last_run_at,
            do: " (last checked #{Calendar.strftime(s.last_run_at, "%Y-%m-%d %H:%M")})",
            else: ""

        "- #{s.source_type}: \"#{s.name}\"#{status}#{last}"
      end)

    axioms =
      Enum.map(ExCortex.Lexicon.list_axioms(), fn a -> "- #{a.name}" end)

    engram_count = ExCortex.Repo.aggregate(ExCortex.Memory.Engram, :count)

    sections = ["## Available Data Sources"]
    sections = if senses == [], do: sections, else: sections ++ ["### Senses\n" <> Enum.join(senses, "\n")]
    sections = if axioms == [], do: sections, else: sections ++ ["### Axioms\n" <> Enum.join(axioms, "\n")]
    sections = sections ++ ["### Memory\n- #{engram_count} engrams in store"]

    Enum.join(sections, "\n\n")
  end

  defp gather_signal_context(question) do
    import Ecto.Query

    # Pull recent active signals, prioritize by recency
    signals =
      ExCortex.Repo.all(from(s in Signal, where: s.status == "active", order_by: [desc: s.inserted_at], limit: 20))

    # Score relevance by keyword overlap with the question
    question_words =
      question
      |> String.downcase()
      |> String.split(~r/\W+/, trim: true)
      |> MapSet.new()

    scored =
      signals
      |> Enum.map(fn s ->
        signal_words =
          "#{s.title} #{Enum.join(s.tags || [], " ")}"
          |> String.downcase()
          |> String.split(~r/\W+/, trim: true)
          |> MapSet.new()

        overlap = question_words |> MapSet.intersection(signal_words) |> MapSet.size()
        {s, overlap}
      end)
      |> Enum.sort_by(fn {_s, score} -> score end, :desc)
      |> Enum.take(5)
      |> Enum.map(fn {s, _score} -> s end)

    if scored == [] do
      ""
    else
      entries =
        Enum.map(scored, fn s ->
          age = format_signal_age(s.inserted_at)
          body = String.slice(s.body || "", 0, 2000)
          tags = if s.tags == [], do: "", else: " [#{Enum.join(s.tags, ", ")}]"
          "### #{s.title}#{tags}\n*#{age} · #{s.source || "system"}*\n\n#{body}"
        end)

      "## Dashboard Signals (recent digests and reports)\n\n" <> Enum.join(entries, "\n\n---\n\n")
    end
  end

  defp format_signal_age(nil), do: "unknown"

  defp format_signal_age(inserted_at) do
    diff = DateTime.diff(DateTime.utc_now(), inserted_at, :minute)

    cond do
      diff < 60 -> "#{diff}m ago"
      diff < 1440 -> "#{div(diff, 60)}h ago"
      true -> "#{div(diff, 1440)}d ago"
    end
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

  defp provider_for("claude_" <> _), do: "claude"
  defp provider_for(_), do: "ollama"
end
