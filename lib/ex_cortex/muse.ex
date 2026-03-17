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
  alias ExCortex.Tools.SearchObsidianContent

  require Logger

  @system_prompt """
  You are Muse, a data-grounded assistant with access to the user's personal knowledge base, dashboard signals, and tools.
  Answer questions concisely and accurately.

  YOUR TOOLS:

  Knowledge & Memory:
  - query_memory — search the engram store (saved knowledge, past run outputs, notes)
  - query_axiom — query reference datasets (sports teams, stock tickers, WCAG criteria, currencies, regulatory frameworks)
  - list_sources — see what data sources and senses are configured

  Obsidian Vault (the user's personal notes — ALWAYS try these for personal questions):
  - search_obsidian — search notes by title (fast, fuzzy). Use query="" to list all notes.
  - search_obsidian_content — search INSIDE note bodies. Use this for: todos ("- [ ]"), specific phrases, tags, dates, anything inside notes.
  - read_obsidian — read a specific note's full content by path
  - read_obsidian_frontmatter — read a note's YAML frontmatter metadata

  Email:
  - search_email — search emails by query (notmuch syntax)
  - read_email — read a specific email by message ID

  Web & URLs:
  - fetch_url — fetch and read a web page
  - web_search — search the web via DuckDuckGo

  GitHub:
  - search_github — search a GitHub repo (code, issues, PRs)
  - read_github_issue — read a specific GitHub issue or PR
  - list_github_notifications — list recent GitHub notifications

  Files & Documents:
  - read_file — read a local file
  - list_files — list files in a directory
  - read_pdf — extract text from a PDF
  - convert_document — convert documents between formats (via pandoc)
  - read_image_text — OCR text from an image
  - describe_image — describe an image's visual content
  - transcribe_audio — transcribe audio/video to text
  - analyze_video — analyze video content

  Data Processing:
  - jq_query — run jq queries against JSON data
  - run_sandbox — run allowlisted shell commands (mix test, mix credo, etc.)
  - query_jaeger — query distributed traces from Jaeger

  Nextcloud:
  - search_nextcloud — search Nextcloud files
  - read_nextcloud — read a Nextcloud file
  - read_nextcloud_notes — read Nextcloud Notes

  PRIORITIES — what to check first:
  - Recent news, digests, summaries → Dashboard Signals context (already provided below if relevant)
  - Notes, ideas, personal knowledge, todos, journal → search_obsidian or search_obsidian_content
  - Open todos or checklists → search_obsidian_content(query: "- [ ]")
  - Past knowledge, stored facts → query_memory
  - Emails → search_email
  - Code, repos, issues → search_github
  - Reference data (teams, tickers, standards) → query_axiom
  - Current web content → fetch_url or web_search

  RULES:
  - USE YOUR TOOLS. Never say "I can't access that" without trying the relevant tool first.
  - When context includes links, include them in your answer.
  - If neither context nor tools can answer, say so honestly rather than guessing.
  - You can READ but not WRITE — you cannot create notes, send emails, or modify files in this mode.
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

  @doc "Gather RAG context from signals, engrams, axioms, and Obsidian."
  def gather_context(question, filters \\ []) do
    source_context = gather_source_context()
    signal_context = gather_signal_context(question)
    obsidian_context = gather_obsidian_context(question)
    engram_context = gather_engram_context(question, filters)
    axiom_context = gather_axiom_context(question)

    email_context = gather_email_context(question)

    [source_context, signal_context, obsidian_context, email_context, engram_context, axiom_context]
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
    utc = if is_struct(inserted_at, NaiveDateTime), do: DateTime.from_naive!(inserted_at, "Etc/UTC"), else: inserted_at
    diff = DateTime.diff(DateTime.utc_now(), utc, :minute)

    cond do
      diff < 60 -> "#{diff}m ago"
      diff < 1440 -> "#{div(diff, 60)}h ago"
      true -> "#{div(diff, 1440)}d ago"
    end
  end

  @obsidian_triggers ~w(obsidian note notes vault todo todos task tasks checklist journal daily)

  defp gather_obsidian_context(question) do
    q_lower = String.downcase(question)
    relevant? = Enum.any?(@obsidian_triggers, &String.contains?(q_lower, &1))

    if relevant? do
      results = []

      # If asking about todos/tasks, search for unchecked checkboxes
      results =
        if String.contains?(q_lower, "todo") or String.contains?(q_lower, "task") or
             String.contains?(q_lower, "checklist") do
          case SearchObsidianContent.call(%{"query" => "- [ ]"}) do
            {:ok, content} -> results ++ ["### Open Todos\n#{content}"]
            _ -> results
          end
        else
          results
        end

      # If asking about journal/daily, fetch today's daily note
      results =
        if String.contains?(q_lower, "journal") or String.contains?(q_lower, "daily") or
             String.contains?(q_lower, "today") do
          today = Calendar.strftime(Date.utc_today(), "%Y-%m-%d")

          case ExCortex.Tools.ReadObsidian.call(%{"path" => "journal/#{today}.md"}) do
            {:ok, content} -> results ++ ["### Daily Note (#{today})\n#{content}"]
            _ -> results
          end
        else
          results
        end

      # General note search based on question keywords
      results =
        if results == [] do
          search_terms =
            q_lower
            |> String.replace(~r/\b(how|many|what|are|the|my|in|do|i|have|of|a|an|is)\b/, "")
            |> String.replace(~r/\b(obsidian|notes?|vault)\b/, "")
            |> String.trim()

          if search_terms == "" do
            # Empty search — list all notes
            case ExCortex.Tools.SearchObsidian.call(%{"query" => ""}) do
              {:ok, content} -> results ++ ["### All Notes\n#{content}"]
              _ -> results
            end
          else
            case SearchObsidianContent.call(%{"query" => search_terms}) do
              {:ok, content} when content != "" -> results ++ ["### Obsidian Search: #{search_terms}\n#{content}"]
              _ -> results
            end
          end
        else
          results
        end

      if results == [] do
        ""
      else
        "## Obsidian Vault\n\n" <> Enum.join(results, "\n\n")
      end
    else
      ""
    end
  end

  @email_triggers ~w(email mail inbox message sent unread newsletter)

  defp gather_email_context(question) do
    q_lower = String.downcase(question)
    relevant? = Enum.any?(@email_triggers, &String.contains?(q_lower, &1))

    if relevant? do
      # Extract search terms — strip common words and email-related noise
      search_terms =
        q_lower
        |> String.replace(~r/\b(how|many|what|are|the|my|in|do|i|have|of|a|an|is|any|from|about|show|me|get)\b/, "")
        |> String.replace(~r/\b(email|emails|mail|inbox|message|messages|unread)\b/, "")
        |> String.trim()

      # Build notmuch query
      query =
        cond do
          String.contains?(q_lower, "unread") -> "tag:unread"
          String.contains?(q_lower, "newsletter") -> "tag:newsletter OR folder:Newsletter"
          search_terms != "" -> search_terms
          true -> "tag:inbox date:7days.."
        end

      case ExCortex.Tools.SearchEmail.call(%{"query" => query, "limit" => "10"}) do
        {:ok, content} when content != "" ->
          "## Email\n\n### Search: #{query}\n#{content}"

        _ ->
          ""
      end
    else
      ""
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
