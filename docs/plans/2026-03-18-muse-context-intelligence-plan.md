# Muse Context Intelligence Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Make Muse intelligently select which context providers to run and with what parameters, using a fast local LLM classifier, and add temporal daily note support so questions like "what's in my brain dump this week" work.

**Architecture:** A new `Muse.Classifier` module calls ministral-3:8b to classify the question into structured provider configs. The Obsidian provider gains temporal range support (read last N daily notes) and section extraction (pull specific callout blocks). `Muse.gather_context` uses the classifier output to dynamically build provider configs instead of using a static list. Falls back to current behavior on classifier failure.

**Tech Stack:** Elixir, ExCortex.LLM.Ollama (ministral-3:8b), ExCortex.ContextProviders

---

### Task 1: Obsidian Section Extraction

Add the ability to extract specific callout sections from daily note content.

**Files:**
- Modify: `lib/ex_cortex/context_providers/obsidian.ex`
- Test: `test/ex_cortex/context_providers/obsidian_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_cortex/context_providers/obsidian_test.exs
defmodule ExCortex.ContextProviders.ObsidianTest do
  use ExUnit.Case, async: true

  alias ExCortex.ContextProviders.Obsidian

  describe "extract_sections/2" do
    test "extracts a single callout section" do
      note = """
      # 2026-03-18

      > [!abstract] brain dump
      > you don't have to organize it. just capture it.
      > thought about making muse smarter
      > another captured idea

      > [!todo] todo
      > - [ ] fix the tests
      > - [x] update CLAUDE.md
      """

      result = Obsidian.extract_sections(note, ["brain_dump"])
      assert String.contains?(result, "thought about making muse smarter")
      assert String.contains?(result, "another captured idea")
      refute String.contains?(result, "fix the tests")
    end

    test "extracts multiple sections" do
      note = """
      > [!abstract] brain dump
      > idea one

      > [!todo] todo
      > - [ ] task one

      > [!tip] stuff that came up
      > remember to check X
      """

      result = Obsidian.extract_sections(note, ["brain_dump", "stuff_that_came_up"])
      assert String.contains?(result, "idea one")
      assert String.contains?(result, "remember to check X")
      refute String.contains?(result, "task one")
    end

    test "returns full content for [all]" do
      note = "# Daily Note\nSome content"
      assert note == Obsidian.extract_sections(note, ["all"])
    end

    test "returns empty string when section not found" do
      note = "> [!todo] todo\n> stuff"
      assert "" == Obsidian.extract_sections(note, ["brain_dump"])
    end

    test "handles section name normalization" do
      note = "> [!abstract] brain dump\n> content here"
      result = Obsidian.extract_sections(note, ["brain_dump"])
      assert String.contains?(result, "content here")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/context_providers/obsidian_test.exs`
Expected: FAIL — function not defined

**Step 3: Implement extract_sections/2**

Add to `lib/ex_cortex/context_providers/obsidian.ex`:

```elixir
@doc "Extract specific callout sections from note content. Section names use underscores (brain_dump → 'brain dump')."
def extract_sections(content, ["all"]), do: content

def extract_sections(content, section_names) do
  # Normalize section names: brain_dump → "brain dump"
  targets = Enum.map(section_names, &String.replace(&1, "_", " "))

  content
  |> String.split("\n")
  |> extract_matching_callouts(targets, nil, [], [])
  |> Enum.join("\n\n")
  |> String.trim()
end

defp extract_matching_callouts([], _targets, _current, current_lines, acc) do
  if current_lines != [], do: acc ++ [Enum.join(current_lines, "\n")], else: acc
end

defp extract_matching_callouts([line | rest], targets, current, current_lines, acc) do
  case Regex.run(~r/^>\s*\[!(\w+)\]\s*(.+)/i, line) do
    [_, _type, title] ->
      # Flush previous section if it was matching
      acc = if current_lines != [], do: acc ++ [Enum.join(current_lines, "\n")], else: acc
      normalized_title = title |> String.trim() |> String.downcase()

      if Enum.any?(targets, &(normalized_title =~ &1)) do
        extract_matching_callouts(rest, targets, :matching, [], acc)
      else
        extract_matching_callouts(rest, targets, :skipping, [], acc)
      end

    _ ->
      if current == :matching and String.starts_with?(line, ">") do
        # Strip the > prefix and trim
        stripped = line |> String.replace_prefix("> ", "") |> String.replace_prefix(">", "")
        extract_matching_callouts(rest, targets, current, current_lines ++ [stripped], acc)
      else
        if current == :matching do
          # Non-> line ends the callout
          acc = if current_lines != [], do: acc ++ [Enum.join(current_lines, "\n")], else: acc
          extract_matching_callouts(rest, targets, nil, [], acc)
        else
          extract_matching_callouts(rest, targets, current, current_lines, acc)
        end
      end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/context_providers/obsidian_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_cortex/context_providers/obsidian.ex test/ex_cortex/context_providers/obsidian_test.exs
git commit -m "feat: Obsidian section extraction for callout blocks"
```

---

### Task 2: Temporal Daily Note Reading

Add `gather_daily_range/2` that reads multiple daily notes with optional section filtering.

**Files:**
- Modify: `lib/ex_cortex/context_providers/obsidian.ex`
- Test: `test/ex_cortex/context_providers/obsidian_test.exs` (add cases)

**Step 1: Write the failing test**

Add to the existing test file:

```elixir
describe "date_range_for/1" do
  test "today returns single date" do
    assert [Date.utc_today()] == Obsidian.date_range_for("today")
  end

  test "yesterday returns yesterday" do
    assert [Date.add(Date.utc_today(), -1)] == Obsidian.date_range_for("yesterday")
  end

  test "week returns 7 dates" do
    dates = Obsidian.date_range_for("week")
    assert length(dates) == 7
    assert hd(dates) == Date.add(Date.utc_today(), -6)
    assert List.last(dates) == Date.utc_today()
  end

  test "month returns 30 dates" do
    dates = Obsidian.date_range_for("month")
    assert length(dates) == 30
  end

  test "defaults to today for unknown range" do
    assert [Date.utc_today()] == Obsidian.date_range_for("unknown")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/context_providers/obsidian_test.exs`
Expected: FAIL

**Step 3: Implement date_range_for/1 and gather_daily_range/2**

Add to `obsidian.ex`:

```elixir
@doc "Returns a list of dates for the given time range."
def date_range_for("today"), do: [Date.utc_today()]
def date_range_for("yesterday"), do: [Date.add(Date.utc_today(), -1)]

def date_range_for("week") do
  today = Date.utc_today()
  Enum.map(6..0//-1, &Date.add(today, -&1))
end

def date_range_for("month") do
  today = Date.utc_today()
  Enum.map(29..0//-1, &Date.add(today, -&1))
end

def date_range_for(_), do: [Date.utc_today()]
```

Also add `gather_daily_range/2` (private, used by the provider when classifier provides time_range + sections):

```elixir
defp gather_daily_range(time_range, sections) do
  dates = date_range_for(time_range)

  results =
    Enum.flat_map(dates, fn date ->
      date_str = Calendar.strftime(date, "%Y-%m-%d")

      case ReadObsidian.call(%{"path" => "journal/#{date_str}.md"}) do
        {:ok, content} when content != "" ->
          filtered =
            if sections == ["all"] do
              content
            else
              extract_sections(content, sections)
            end

          if filtered != "" do
            ["### #{date_str}\n#{filtered}"]
          else
            []
          end

        _ ->
          []
      end
    end)

  if results == [] do
    ""
  else
    "## Daily Notes (#{time_range})\n\n" <> Enum.join(results, "\n\n---\n\n")
  end
end
```

**Step 4: Update the `build/3` function to accept new config keys**

The `build` function already dispatches on `mode`. Add handling for when config includes `"time_range"` and `"sections"`:

```elixir
case mode do
  "auto" -> auto_gather(input, config)
  "daily_range" -> gather_daily_range(Map.get(config, "time_range", "today"), Map.get(config, "sections", ["all"]))
  # ... existing modes
end
```

**Step 5: Run tests**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/context_providers/obsidian_test.exs`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/ex_cortex/context_providers/obsidian.ex test/ex_cortex/context_providers/obsidian_test.exs
git commit -m "feat: temporal daily note reading with section filtering"
```

---

### Task 3: Question Classifier

Create `ExCortex.Muse.Classifier` that uses ministral-3:8b to classify questions.

**Files:**
- Create: `lib/ex_cortex/muse/classifier.ex`
- Test: `test/ex_cortex/muse/classifier_test.exs`

**Step 1: Write the failing test**

```elixir
# test/ex_cortex/muse/classifier_test.exs
defmodule ExCortex.Muse.ClassifierTest do
  use ExUnit.Case, async: true

  alias ExCortex.Muse.Classifier

  describe "parse_result/1" do
    test "parses valid JSON classification" do
      json = ~s({"providers": ["obsidian", "engrams"], "time_range": "week", "obsidian_mode": "daily", "obsidian_sections": ["brain_dump"], "search_terms": "brain dump"})
      result = Classifier.parse_result(json)
      assert result.providers == ["obsidian", "engrams"]
      assert result.time_range == "week"
      assert result.obsidian_mode == "daily"
      assert result.obsidian_sections == ["brain_dump"]
      assert result.search_terms == "brain dump"
    end

    test "returns default on invalid JSON" do
      result = Classifier.parse_result("not json")
      assert result == Classifier.default_classification()
    end

    test "validates provider names" do
      json = ~s({"providers": ["obsidian", "unknown_thing", "engrams"]})
      result = Classifier.parse_result(json)
      assert result.providers == ["obsidian", "engrams"]
    end

    test "validates time_range" do
      json = ~s({"providers": ["engrams"], "time_range": "century"})
      result = Classifier.parse_result(json)
      assert result.time_range == "all"
    end
  end

  describe "default_classification/0" do
    test "includes all providers" do
      d = Classifier.default_classification()
      assert "obsidian" in d.providers
      assert "engrams" in d.providers
      assert "signals" in d.providers
    end
  end

  describe "build_providers_from_classification/1" do
    test "builds obsidian provider with time_range and sections" do
      classification = %{
        providers: ["obsidian"],
        time_range: "week",
        obsidian_mode: "daily",
        obsidian_sections: ["brain_dump"],
        search_terms: ""
      }

      providers = Classifier.build_providers_from_classification(classification)
      obsidian = Enum.find(providers, &(&1["type"] == "obsidian"))
      assert obsidian["mode"] == "daily_range"
      assert obsidian["time_range"] == "week"
      assert obsidian["sections"] == ["brain_dump"]
    end

    test "always includes sources and engrams" do
      classification = %{providers: ["signals"], time_range: "today", obsidian_mode: "auto", obsidian_sections: ["all"], search_terms: ""}
      providers = Classifier.build_providers_from_classification(classification)
      types = Enum.map(providers, & &1["type"])
      assert "sources" in types
      assert "engrams" in types
      assert "signals" in types
    end

    test "builds search mode when obsidian_mode is search" do
      classification = %{providers: ["obsidian"], time_range: "all", obsidian_mode: "search", obsidian_sections: ["all"], search_terms: "project ideas"}
      providers = Classifier.build_providers_from_classification(classification)
      obsidian = Enum.find(providers, &(&1["type"] == "obsidian"))
      assert obsidian["mode"] == "search"
      assert obsidian["query"] == "project ideas"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/muse/classifier_test.exs`
Expected: FAIL

**Step 3: Implement the Classifier**

```elixir
# lib/ex_cortex/muse/classifier.ex
defmodule ExCortex.Muse.Classifier do
  @moduledoc """
  Classifies user questions to determine which context providers Muse should use.
  Uses a fast local LLM (ministral-3:8b) to parse intent.
  """

  require Logger

  @valid_providers ~w(obsidian signals engrams email axioms sources)
  @valid_time_ranges ~w(today yesterday week month all)
  @valid_obsidian_modes ~w(daily search todos list auto)
  @valid_sections ~w(brain_dump todo stuff_that_came_up whats_happening all)

  @classifier_model "ministral-3:8b"

  @classifier_prompt """
  You are a question classifier. Given a user question, determine which data sources to search and how.

  Respond with ONLY valid JSON (no markdown, no explanation):

  {
    "providers": ["obsidian", "engrams"],
    "time_range": "today",
    "obsidian_mode": "daily",
    "obsidian_sections": ["all"],
    "search_terms": ""
  }

  FIELD VALUES:
  - providers: one or more of: obsidian, signals, engrams, email, axioms, sources
  - time_range: today, yesterday, week, month, all
  - obsidian_mode: daily (read daily notes), search (search vault), todos (find todos), list (list notes), auto (let the system decide)
  - obsidian_sections: brain_dump, todo, stuff_that_came_up, whats_happening, all
  - search_terms: key terms extracted from the question (empty string if not needed)

  RULES:
  - Personal notes, brain dumps, journal, daily entries → obsidian + daily mode
  - "this week", "recently", "lately" → time_range: week
  - "yesterday" → time_range: yesterday
  - "today" → time_range: today
  - "brain dump" or "captured" or "dumped" → obsidian_sections: ["brain_dump"]
  - Todos, tasks, checklist → obsidian + todos mode
  - Dashboard, metrics, status → signals
  - Memory, past knowledge, stored → engrams
  - Email, inbox, messages → email
  - Reference data, standards, lookup → axioms
  - If unsure, include obsidian + engrams + signals (the safe default)
  """

  @doc "Classify a question. Returns a classification map. Falls back to defaults on any failure."
  def classify(question) do
    case ExCortex.LLM.complete("ollama", @classifier_model, @classifier_prompt, question) do
      {:ok, response} ->
        parse_result(response)

      {:error, reason} ->
        Logger.debug("[Classifier] LLM call failed: #{inspect(reason)}, using defaults")
        default_classification()
    end
  rescue
    e ->
      Logger.debug("[Classifier] Error: #{Exception.message(e)}, using defaults")
      default_classification()
  end

  @doc "Parse LLM response JSON into a validated classification map."
  def parse_result(text) do
    # Extract JSON from response (model might wrap in markdown)
    json_str =
      case Regex.run(~r/\{[^}]*"providers"[^}]*\}/s, text) do
        [match] -> match
        _ -> text
      end

    case Jason.decode(json_str) do
      {:ok, parsed} -> validate(parsed)
      {:error, _} -> default_classification()
    end
  end

  @doc "Default classification — all major providers, no special filtering."
  def default_classification do
    %{
      providers: ["obsidian", "signals", "engrams", "email", "axiom_search"],
      time_range: "today",
      obsidian_mode: "auto",
      obsidian_sections: ["all"],
      search_terms: ""
    }
  end

  @doc "Build context provider configs from a classification result."
  def build_providers_from_classification(classification) do
    requested = classification.providers

    # Always include sources (cheap inventory) and engrams (core memory)
    base = [
      %{"type" => "sources"},
      %{"type" => "engrams", "tags" => [], "limit" => 10, "sort" => "top"}
    ]

    optional =
      Enum.flat_map(requested, fn
        "obsidian" -> [build_obsidian_config(classification)]
        "signals" -> [%{"type" => "signals"}]
        "email" -> [%{"type" => "email", "mode" => "auto"}]
        "axioms" -> [%{"type" => "axiom_search"}]
        "sources" -> []  # already in base
        "engrams" -> []  # already in base
        _ -> []
      end)

    base ++ optional
  end

  defp build_obsidian_config(classification) do
    case classification.obsidian_mode do
      "daily" ->
        if classification.time_range != "today" or classification.obsidian_sections != ["all"] do
          %{
            "type" => "obsidian",
            "mode" => "daily_range",
            "time_range" => classification.time_range,
            "sections" => classification.obsidian_sections
          }
        else
          %{"type" => "obsidian", "mode" => "auto"}
        end

      "search" ->
        %{"type" => "obsidian", "mode" => "search", "query" => classification.search_terms}

      "todos" ->
        %{"type" => "obsidian", "mode" => "todos"}

      "list" ->
        %{"type" => "obsidian", "mode" => "list"}

      _ ->
        %{"type" => "obsidian", "mode" => "auto"}
    end
  end

  defp validate(parsed) when is_map(parsed) do
    %{
      providers: validate_list(parsed["providers"], @valid_providers),
      time_range: validate_value(parsed["time_range"], @valid_time_ranges, "all"),
      obsidian_mode: validate_value(parsed["obsidian_mode"], @valid_obsidian_modes, "auto"),
      obsidian_sections: validate_list(parsed["obsidian_sections"], @valid_sections, ["all"]),
      search_terms: parsed["search_terms"] || ""
    }
  end

  defp validate(_), do: default_classification()

  defp validate_list(nil, _valid), do: default_classification().providers
  defp validate_list(nil, _valid, default), do: default

  defp validate_list(items, valid) when is_list(items) do
    filtered = Enum.filter(items, &(&1 in valid))
    if filtered == [], do: default_classification().providers, else: filtered
  end

  defp validate_list(items, valid, default) when is_list(items) do
    filtered = Enum.filter(items, &(&1 in valid))
    if filtered == [], do: default, else: filtered
  end

  defp validate_list(_, _, default), do: default

  defp validate_value(nil, _valid, default), do: default
  defp validate_value(val, valid, default), do: if(val in valid, do: val, else: default)
end
```

**Step 4: Run test to verify it passes**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/muse/classifier_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ex_cortex/muse/classifier.ex test/ex_cortex/muse/classifier_test.exs
git commit -m "feat: Muse question classifier using local LLM"
```

---

### Task 4: Wire Classifier into Muse.gather_context

**Files:**
- Modify: `lib/ex_cortex/muse.ex:170-186`
- Test: `test/ex_cortex/muse_test.exs` (update existing tests)

**Step 1: Update gather_context/2**

Replace the static `@muse_providers` usage with classifier-driven selection:

```elixir
def gather_context(question, filters \\ []) do
  classification = ExCortex.Muse.Classifier.classify(question)

  providers =
    classification
    |> ExCortex.Muse.Classifier.build_providers_from_classification()
    |> maybe_apply_filters(filters)

  thought = %{name: "Muse", id: nil}
  ContextProvider.assemble(providers, thought, question)
end

defp maybe_apply_filters(providers, []), do: providers

defp maybe_apply_filters(providers, filters) do
  Enum.map(providers, fn
    %{"type" => "engrams"} = p -> Map.put(p, "tags", filters)
    p -> p
  end)
end
```

Keep `@muse_providers` as the fallback (used by `Classifier.default_classification`).

**Step 2: Run existing Muse tests**

Run: `cd /home/andrew/projects/ex_cortex && mix test test/ex_cortex/muse_test.exs`
Expected: PASS (existing behavior preserved via classifier defaults)

**Step 3: Commit**

```bash
git add lib/ex_cortex/muse.ex
git commit -m "feat: wire classifier into Muse.gather_context"
```

---

### Task 5: Format + Full Test Suite

**Step 1: Format**

Run: `cd /home/andrew/projects/ex_cortex && mix format`

**Step 2: Full test suite**

Run: `cd /home/andrew/projects/ex_cortex && mix test`
Expected: 544+ tests, 0 failures

**Step 3: Commit**

```bash
git add -A && git commit -m "chore: format"
```
