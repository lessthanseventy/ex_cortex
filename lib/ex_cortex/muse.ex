defmodule ExCortex.Muse do
  @moduledoc """
  Data-grounded single-step LLM queries.

  Wonderings use no context. Musings pull context via the ContextProvider
  system — signals, obsidian, email, engrams, axioms, and data sources.
  Both persist the Q&A to the thoughts table.
  """

  alias ExCortex.ContextProviders.ContextProvider
  alias ExCortex.LLM
  alias ExCortex.Thoughts
  alias ExCortex.Tools.Registry

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
  - obsidian_list_todos — list open todos from today's (or any day's) daily note, grouped by section
  - obsidian_toggle_todo — mark a todo as done or undone by line number or text match
  - obsidian_add_todo — add a new todo to today's daily note (in the [!todo] section by default)
  - daily_note_write — write content into a specific section of today's daily note (e.g. "brain dump", "stuff that came up"). Content is added inside the matching callout block.

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
  - You can write to the user's Obsidian daily note sections (daily_note_write), add todos (obsidian_add_todo), and toggle todos (obsidian_toggle_todo).
  - You CANNOT send emails, create files, modify code, or push to git in this mode.
  """

  @wonder_system_prompt """
  You are a helpful assistant. Answer questions concisely and accurately.
  """

  # Context providers that Muse uses for RAG grounding.
  # Each is a config map matching the ContextProvider behaviour.
  # "auto" mode providers detect relevance from the input question.
  @muse_providers [
    %{"type" => "sources"},
    %{"type" => "signals"},
    %{"type" => "obsidian", "mode" => "auto"},
    %{"type" => "email", "mode" => "auto"},
    %{"type" => "engrams", "tags" => [], "limit" => 10, "sort" => "top"},
    %{"type" => "axiom_search"}
  ]

  @doc """
  Ask a question. Scope determines data grounding:
  - "wonder" — no context, pure LLM
  - "muse" — RAG over all context providers

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
          tools = Registry.list_safe() ++ muse_write_tools()

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

  @doc "Gather RAG context using the context provider system."
  def gather_context(question, filters \\ []) do
    providers =
      if filters == [] do
        @muse_providers
      else
        # Override engram tags if source filters specified
        Enum.map(@muse_providers, fn
          %{"type" => "engrams"} = p -> Map.put(p, "tags", filters)
          p -> p
        end)
      end

    # Build a pseudo-thought map for the provider interface
    thought = %{name: "Muse", id: nil}

    ContextProvider.assemble(providers, thought, question)
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

  # Obsidian write tools Muse is allowed to use
  defp muse_write_tools do
    [
      ExCortex.Tools.DailyNoteWrite.req_llm_tool(),
      ExCortex.Tools.ObsidianAddTodo.req_llm_tool(),
      ExCortex.Tools.ObsidianToggleTodo.req_llm_tool()
    ]
  end
end
