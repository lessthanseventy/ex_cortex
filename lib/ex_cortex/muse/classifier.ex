defmodule ExCortex.Muse.Classifier do
  @moduledoc """
  Classifies user questions into structured provider configs using a fast local LLM.

  Calls ministral-3:8b to determine which context providers are relevant,
  what time range to search, and how to configure Obsidian queries.
  Falls back to safe defaults on any failure.
  """

  require Logger

  @valid_providers ~w(obsidian signals engrams email axioms sources github)
  @valid_time_ranges ~w(today yesterday week month all)
  @valid_obsidian_modes ~w(daily search todos list auto)
  @valid_sections ~w(brain_dump todo stuff_that_came_up whats_happening what_happened all)

  @system_prompt """
  You are a question classifier for a personal knowledge system. Given a user question,
  classify it into structured JSON to route to the right data providers.

  Respond with ONLY valid JSON (no markdown, no explanation):

  {
    "providers": ["obsidian", "engrams"],
    "time_range": "week",
    "obsidian_mode": "daily",
    "obsidian_sections": ["brain_dump"],
    "search_terms": "extracted search terms"
  }

  Rules:
  - providers: which data sources to query. Options: obsidian, signals, engrams, email, axioms, sources, github
  - time_range: today, yesterday, week, month, all
  - obsidian_mode: daily (journal notes), search (vault search), todos (task lists), list (list notes), auto (let system decide)
  - obsidian_sections: brain_dump, todo, stuff_that_came_up, whats_happening, what_happened, all

  Classification rules:
  - Personal notes, brain dumps, journal, diary → obsidian + daily mode
  - "this week", "past week" → time_range: week
  - "today" → time_range: today
  - "yesterday" → time_range: yesterday
  - "brain dump" → obsidian_sections: ["brain_dump"]
  - "what did I do", "get done", "accomplished", "completed" → obsidian_sections: ["what_happened"]
  - "what should I do", "what's on my plate", "what's happening" → obsidian_sections: ["whats_happening"]
  - "todos", "tasks", "to do" → obsidian + todos mode
  - Dashboard, metrics, status → signals
  - Memory, past knowledge, "remember when" → engrams
  - Email, messages, inbox → email
  - Reference data, datasets, lookup → axioms
  - Code, PRs, issues, repo, commits → github
  - If unsure, default to: obsidian + engrams + signals with time_range: all and obsidian_mode: auto
  """

  @doc """
  Classifies a user question by calling the local LLM.

  Returns a classification map on success, or the default classification on failure.
  """
  @spec classify(String.t()) :: map()
  def classify(question) do
    case ExCortex.LLM.complete("ollama", "ministral-3:8b", @system_prompt, question) do
      {:ok, response} ->
        case parse_result(response) do
          {:ok, classification} -> classification
          {:error, _} -> default_classification()
        end

      {:error, reason} ->
        Logger.warning("Classifier LLM call failed: #{inspect(reason)}, using defaults")
        default_classification()
    end
  end

  @doc """
  Parses and validates an LLM response into a classification map.

  Extracts JSON from text (handles markdown code blocks), decodes it,
  and validates field values against known lists.
  """
  @spec parse_result(String.t()) :: {:ok, map()} | {:error, :invalid_json}
  def parse_result(text) do
    text
    |> extract_json()
    |> decode_and_validate()
  end

  @doc """
  Converts a classification map into provider configs for ContextProvider.assemble.

  Always includes `sources` (cheap inventory) and `engrams` (core memory).
  """
  @spec build_providers_from_classification(map()) :: [map()]
  def build_providers_from_classification(classification) do
    base = [
      %{"type" => "sources"},
      %{"type" => "engrams"}
    ]

    extra =
      classification.providers
      |> Enum.reject(&(&1 in ["sources", "engrams"]))
      |> Enum.map(&build_provider(&1, classification))
      |> Enum.reject(&is_nil/1)

    base ++ extra
  end

  @doc """
  Returns a safe default classification covering core providers.
  """
  @spec default_classification() :: map()
  def default_classification do
    %{
      providers: ["obsidian", "engrams", "signals"],
      time_range: "all",
      obsidian_mode: "auto",
      obsidian_sections: ["all"],
      search_terms: ""
    }
  end

  # Private helpers

  defp extract_json(text) do
    case Regex.run(~r/```(?:json)?\s*\n?(.*?)\n?\s*```/s, text) do
      [_, json] -> String.trim(json)
      nil -> String.trim(text)
    end
  end

  defp decode_and_validate(json_string) do
    case Jason.decode(json_string) do
      {:ok, decoded} when is_map(decoded) ->
        {:ok, validate(decoded)}

      _ ->
        {:error, :invalid_json}
    end
  end

  defp validate(decoded) do
    providers =
      decoded
      |> Map.get("providers", [])
      |> List.wrap()
      |> Enum.filter(&(&1 in @valid_providers))

    time_range =
      decoded
      |> Map.get("time_range", "all")
      |> validate_value(@valid_time_ranges, "all")

    obsidian_mode =
      decoded
      |> Map.get("obsidian_mode", "auto")
      |> validate_value(@valid_obsidian_modes, "auto")

    obsidian_sections =
      decoded
      |> Map.get("obsidian_sections", ["all"])
      |> List.wrap()
      |> Enum.filter(&(&1 in @valid_sections))

    obsidian_sections = if obsidian_sections == [], do: ["all"], else: obsidian_sections

    search_terms =
      decoded
      |> Map.get("search_terms", "")
      |> to_string()

    %{
      providers: providers,
      time_range: time_range,
      obsidian_mode: obsidian_mode,
      obsidian_sections: obsidian_sections,
      search_terms: search_terms
    }
  end

  defp validate_value(value, valid_list, default) do
    if value in valid_list, do: value, else: default
  end

  defp build_provider("obsidian", classification) do
    case classification.obsidian_mode do
      "daily" when classification.time_range != "today" or classification.obsidian_sections != ["all"] ->
        %{
          "type" => "obsidian",
          "mode" => "daily_range",
          "time_range" => classification.time_range,
          "sections" => classification.obsidian_sections
        }

      "search" ->
        %{
          "type" => "obsidian",
          "mode" => "search",
          "query" => classification.search_terms
        }

      "todos" ->
        %{"type" => "obsidian", "mode" => "todos"}

      _ ->
        %{"type" => "obsidian", "mode" => "auto"}
    end
  end

  defp build_provider("signals", _classification) do
    %{"type" => "signals"}
  end

  defp build_provider("email", _classification) do
    %{"type" => "email", "mode" => "auto"}
  end

  defp build_provider("axioms", _classification) do
    %{"type" => "axiom_search"}
  end

  defp build_provider("github", _classification), do: nil

  defp build_provider(_unknown, _classification), do: nil

  # ---------------------------------------------------------------------------
  # Tool selection — derive tool categories from provider classification
  # ---------------------------------------------------------------------------

  @tool_groups %{
    "obsidian" => ~w(search_obsidian search_obsidian_content read_obsidian read_obsidian_frontmatter obsidian_list_todos),
    "email" => ~w(search_email read_email),
    "github" => ~w(search_github read_github_issue list_github_notifications),
    "axioms" => ~w(query_axiom),
    "signals" => [],
    "sources" => ~w(list_sources)
  }

  # Always available regardless of classification
  @baseline_tools ~w(query_memory fetch_url web_fetch web_search)

  @doc """
  Returns tool name lists for a classification. Derives tool categories from
  the selected providers, always includes baseline tools (memory, web).
  """
  @spec tools_for_classification(map()) :: [String.t()]
  def tools_for_classification(classification) do
    provider_tools = Enum.flat_map(classification.providers, &Map.get(@tool_groups, &1, []))

    Enum.uniq(@baseline_tools ++ provider_tools)
  end
end
